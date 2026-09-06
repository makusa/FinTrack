//
//  AppLockManager.swift
//  FinTrack
//
//  @Observable singleton — owns all authentication state.
//  Views observe via @Environment(AppLockManager.self).
//

import SwiftUI
import LocalAuthentication
import CryptoKit

// MARK: - Auto-lock delay options

enum AutoLockDelay: Int, CaseIterable, Identifiable {
    case immediately  = 0
    case oneMinute    = 60
    case fiveMinutes  = 300
    case never        = -1

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .immediately: return LanguageManager.shared["lock.delay.immediately"]
        case .oneMinute:   return LanguageManager.shared["lock.delay.1min"]
        case .fiveMinutes: return LanguageManager.shared["lock.delay.5min"]
        case .never:       return LanguageManager.shared["lock.delay.never"]
        }
    }
}

// MARK: - Manager

@Observable
final class AppLockManager {

    static let shared = AppLockManager()

    // MARK: State

    /// Whether the app is currently showing the lock screen.
    private(set) var isLocked: Bool = false

    /// Whether the user has completed the initial account setup.
    private(set) var isSetup: Bool = false

    /// The user's display name.
    private(set) var userName: String = ""

    /// Whether FaceID/TouchID is enabled.
    private(set) var useBiometrics: Bool = false

    /// Auto-lock delay after backgrounding.
    private(set) var autoLockDelay: AutoLockDelay = .immediately

    /// Number of consecutive failed PIN attempts.
    private(set) var failedAttempts: Int = 0

    /// Whether the PIN entry is temporarily blocked.
    private(set) var isBlocked: Bool = false

    private(set) var blockUntil: Date? = nil

    // Biometric capability on this device
    private(set) var biometricType: LABiometryType = .none

    private var backgroundDate: Date? = nil
    private let maxAttempts = 5

    // MARK: - Init

    private init() {
        #if DEBUG
        // Screenshot harness: skip PIN setup and the lock screen entirely.
        if DemoMode.isActive {
            isSetup  = true
            isLocked = false
            userName = "Régis"
            checkBiometricCapability()
            return
        }
        #endif
        loadFromKeychain()
        checkBiometricCapability()
        // Lock on launch unless the user explicitly chose "never lock".
        // A forced kill + relaunch is treated as a security event for all
        // other delay settings (immediately / 1 min / 5 min).
        if isSetup && autoLockDelay != .never {
            isLocked = true
        }
    }

    // MARK: - Setup (first launch)

    func setup(userName: String, pin: String, useBiometrics: Bool, autoLockDelay: AutoLockDelay) {
        let salt = generateSalt()
        let hash = hashPIN(pin, salt: salt)

        KeychainHelper.set(hash,         forKey: KeychainHelper.Key.pinHash)
        KeychainHelper.set(salt,         forKey: KeychainHelper.Key.pinSalt)
        KeychainHelper.set(userName,     forKey: KeychainHelper.Key.userName)
        KeychainHelper.set(useBiometrics ? "1" : "0", forKey: KeychainHelper.Key.useFaceID)
        KeychainHelper.set("\(autoLockDelay.rawValue)", forKey: KeychainHelper.Key.autoLockSecs)
        KeychainHelper.set("1",          forKey: KeychainHelper.Key.isSetup)

        self.userName       = userName
        self.useBiometrics  = useBiometrics
        self.autoLockDelay  = autoLockDelay
        self.isSetup        = true
        self.isLocked       = false
        self.failedAttempts = 0
    }

    // MARK: - PIN update

    func updatePIN(newPIN: String) {
        let salt = generateSalt()
        let hash = hashPIN(newPIN, salt: salt)
        KeychainHelper.set(hash, forKey: KeychainHelper.Key.pinHash)
        KeychainHelper.set(salt, forKey: KeychainHelper.Key.pinSalt)
    }

    func updateUserName(_ name: String) {
        userName = name
        KeychainHelper.set(name, forKey: KeychainHelper.Key.userName)
    }

    func updateBiometrics(_ enabled: Bool) {
        useBiometrics = enabled
        KeychainHelper.set(enabled ? "1" : "0", forKey: KeychainHelper.Key.useFaceID)
    }

    func updateAutoLockDelay(_ delay: AutoLockDelay) {
        autoLockDelay = delay
        KeychainHelper.set("\(delay.rawValue)", forKey: KeychainHelper.Key.autoLockSecs)
    }

    // MARK: - Lock / Unlock

    func lock() {
        isLocked = true
        failedAttempts = 0
        isBlocked = false
        blockUntil = nil
        // Reset persisted counters — a normal lock is not a suspicious event
        clearBlockedKeychainEntries()
    }

    // MARK: - Biometric unlock result

    enum BiometricResult {
        case success
        case fallback      // user tapped "Enter Passcode" — show PIN
        case cancelled     // user cancelled — do nothing, PIN pad is visible
        case failed        // biometric mismatch — prompt user to use PIN
        case unavailable   // hardware/policy issue — PIN only
    }

    /// Attempt to unlock with FaceID/TouchID.
    /// Returns a typed result so the UI can react appropriately.
    @discardableResult
    func unlockWithBiometrics() async -> BiometricResult {
        let ctx = LAContext()
        var nsError: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                                    error: &nsError) else {
            return .unavailable
        }
        do {
            let reason = LanguageManager.shared["lock.biometric.reason"]
            let ok = try await ctx.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
            if ok { await MainActor.run { unlock() } }
            return ok ? .success : .failed
        } catch let error as LAError {
            switch error.code {
            case .userFallback:            return .fallback    // "Enter Passcode" tapped
            case .userCancel,
                 .systemCancel:            return .cancelled
            case .biometryLockout:         return .unavailable
            case .authenticationFailed:    return .failed
            default:                       return .unavailable
            }
        } catch {
            return .unavailable
        }
    }

    /// Attempt to unlock with PIN. Returns true on success.
    @MainActor
    func unlockWithPIN(_ entered: String) -> Bool {
        guard !isBlocked else { return false }

        guard let storedHash = KeychainHelper.string(forKey: KeychainHelper.Key.pinHash),
              let salt       = KeychainHelper.string(forKey: KeychainHelper.Key.pinSalt)
        else { return false }

        let enteredHash = hashPIN(entered, salt: salt)

        if enteredHash == storedHash {
            unlock()
            return true
        } else {
            failedAttempts += 1
            // Persist the counter immediately — survives app kill
            KeychainHelper.set("\(failedAttempts)", forKey: KeychainHelper.Key.failedAttempts)

            if failedAttempts >= maxAttempts {
                let until = Date().addingTimeInterval(30)
                isBlocked  = true
                blockUntil = until
                // Persist the block expiry — survives app kill
                KeychainHelper.set("\(until.timeIntervalSince1970)",
                                   forKey: KeychainHelper.Key.blockUntil)
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(30))
                    self.clearBlock()
                }
            }
            return false
        }
    }

    // MARK: - App lifecycle

    func handleBackground() {
        guard isSetup else { return }
        backgroundDate = Date()
    }

    func handleForeground() {
        guard isSetup else { return }
        checkBiometricCapability()  // refresh in case user enrolled biometrics since last launch
        guard autoLockDelay != .never else { return }
        // If backgroundDate is nil (e.g. app was killed without going to background first),
        // elapsed = .infinity → always locks. Intentional: kill+relaunch = security event.
        let elapsed = backgroundDate.map { Date().timeIntervalSince($0) } ?? .infinity
        let threshold = TimeInterval(autoLockDelay.rawValue)
        if threshold == 0 || elapsed >= threshold {
            lock()
            if useBiometrics {
                Task { await unlockWithBiometrics() }
            }
        }
        backgroundDate = nil
    }

    // MARK: - Reset (danger zone)

    func resetAccount() {
        KeychainHelper.delete(forKey: KeychainHelper.Key.pinHash)
        KeychainHelper.delete(forKey: KeychainHelper.Key.pinSalt)
        KeychainHelper.delete(forKey: KeychainHelper.Key.userName)
        KeychainHelper.delete(forKey: KeychainHelper.Key.useFaceID)
        KeychainHelper.delete(forKey: KeychainHelper.Key.autoLockSecs)
        KeychainHelper.delete(forKey: KeychainHelper.Key.isSetup)
        KeychainHelper.delete(forKey: KeychainHelper.Key.failedAttempts)
        KeychainHelper.delete(forKey: KeychainHelper.Key.blockUntil)
        userName       = ""
        useBiometrics  = false
        isSetup        = false
        isLocked       = false
        failedAttempts = 0
        isBlocked      = false
        blockUntil     = nil
    }

    // MARK: - Private helpers

    private func unlock() {
        isLocked       = false
        failedAttempts = 0
        isBlocked      = false
        blockUntil     = nil
        clearBlockedKeychainEntries()
    }

    private func loadFromKeychain() {
        isSetup       = KeychainHelper.string(forKey: KeychainHelper.Key.isSetup) == "1"
        userName      = KeychainHelper.string(forKey: KeychainHelper.Key.userName) ?? ""
        useBiometrics = KeychainHelper.string(forKey: KeychainHelper.Key.useFaceID) == "1"
        let rawDelay  = Int(KeychainHelper.string(forKey: KeychainHelper.Key.autoLockSecs) ?? "0") ?? 0
        autoLockDelay = AutoLockDelay(rawValue: rawDelay) ?? .immediately

        // Restore brute-force counters — survives app kill + relaunch
        let storedAttempts = Int(KeychainHelper.string(forKey: KeychainHelper.Key.failedAttempts) ?? "0") ?? 0
        failedAttempts = storedAttempts

        if let rawBlockUntil = KeychainHelper.string(forKey: KeychainHelper.Key.blockUntil),
           let interval = TimeInterval(rawBlockUntil) {
            let until = Date(timeIntervalSince1970: interval)
            if until > Date() {
                // Block is still active — reapply it
                isBlocked  = true
                blockUntil = until
                let remaining = until.timeIntervalSince(Date())
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(remaining))
                    self.clearBlock()
                }
            } else {
                // Block expired while app was closed — clear it
                clearBlockedKeychainEntries()
            }
        }
    }

    /// Clears the in-memory block state AND removes Keychain entries.
    private func clearBlock() {
        isBlocked      = false
        failedAttempts = 0
        blockUntil     = nil
        clearBlockedKeychainEntries()
    }

    private func clearBlockedKeychainEntries() {
        KeychainHelper.set("0", forKey: KeychainHelper.Key.failedAttempts)
        KeychainHelper.delete(forKey: KeychainHelper.Key.blockUntil)
    }

    private func checkBiometricCapability() {
        let ctx = LAContext()
        var error: NSError?
        if ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            biometricType = ctx.biometryType
        } else {
            biometricType = .none
        }
    }

    private func generateSalt() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
    }

    private func hashPIN(_ pin: String, salt: String) -> String {
        let combined = pin + salt
        let data = Data(combined.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Biometric label helper

extension LABiometryType {
    var label: String {
        switch self {
        case .faceID:    return "Face ID"
        case .touchID:   return "Touch ID"
        case .opticID:   return "Optic ID"
        default:         return LanguageManager.shared["lock.biometric.generic"]
        }
    }
    var systemImage: String {
        switch self {
        case .faceID:  return "faceid"
        case .touchID: return "touchid"
        default:       return "person.badge.key"
        }
    }
}
