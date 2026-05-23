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
        loadFromKeychain()
        checkBiometricCapability()
        if isSetup { isLocked = true }
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
    }

    /// Attempt to unlock with FaceID/TouchID.
    func unlockWithBiometrics() async -> Bool {
        let ctx = LAContext()
        var error: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return false
        }
        do {
            let reason = LanguageManager.shared["lock.biometric.reason"]
            let result = try await ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
            if result { await MainActor.run { unlock() } }
            return result
        } catch {
            return false
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
            if failedAttempts >= maxAttempts {
                isBlocked = true
                blockUntil = Date().addingTimeInterval(30)
                // Unblock after 30 s
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(30))
                    self.isBlocked = false
                    self.failedAttempts = 0
                    self.blockUntil = nil
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
        guard autoLockDelay != .never else { return }
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
        userName      = ""
        useBiometrics = false
        isSetup       = false
        isLocked      = false
        failedAttempts = 0
    }

    // MARK: - Private helpers

    private func unlock() {
        isLocked       = false
        failedAttempts = 0
        isBlocked      = false
        blockUntil     = nil
    }

    private func loadFromKeychain() {
        isSetup       = KeychainHelper.string(forKey: KeychainHelper.Key.isSetup) == "1"
        userName      = KeychainHelper.string(forKey: KeychainHelper.Key.userName) ?? ""
        useBiometrics = KeychainHelper.string(forKey: KeychainHelper.Key.useFaceID) == "1"
        let rawDelay  = Int(KeychainHelper.string(forKey: KeychainHelper.Key.autoLockSecs) ?? "0") ?? 0
        autoLockDelay = AutoLockDelay(rawValue: rawDelay) ?? .immediately
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
