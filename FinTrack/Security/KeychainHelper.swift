//
//  KeychainHelper.swift
//  FinTrack
//
//  Minimal, strongly-typed wrapper around Security.framework Keychain APIs.
//  All FinTrack secrets are stored under the service "ca.bmsk.fintrack".
//
//  `synchronizable` (default false) controls iCloud Keychain sync:
//   - false → device-only (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly).
//     Used for auth secrets that must NOT leave the device (PIN hash/salt,
//     anti-brute-force counters, Face ID flag).
//   - true  → follows the user's iCloud Keychain across devices and survives
//     reinstall (kSecAttrAccessibleAfterFirstUnlock — ...ThisDeviceOnly is
//     incompatible with synchronizable). Used for bank connection tokens.
//
//  Synchronizable and non-synchronizable items live in separate namespaces, so
//  reads/writes/deletes must pass the same `synchronizable` value used to store.
//

import Foundation
import Security

enum KeychainHelper {

    private static let service = "ca.bmsk.fintrack"

    // MARK: - Write

    @discardableResult
    static func set(_ value: String, forKey key: String, synchronizable: Bool = false) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        return set(data, forKey: key, synchronizable: synchronizable)
    }

    @discardableResult
    static func set(_ data: Data, forKey key: String, synchronizable: Bool = false) -> Bool {
        // Delete any existing entry first (same namespace).
        delete(forKey: key, synchronizable: synchronizable)

        var query: [CFString: Any] = [
            kSecClass:           kSecClassGenericPassword,
            kSecAttrService:     service,
            kSecAttrAccount:     key,
            kSecValueData:       data,
            kSecAttrAccessible:  synchronizable
                ? kSecAttrAccessibleAfterFirstUnlock
                : kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        if synchronizable {
            query[kSecAttrSynchronizable] = kCFBooleanTrue
        }
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    // MARK: - Read

    static func string(forKey key: String, synchronizable: Bool = false) -> String? {
        guard let data = data(forKey: key, synchronizable: synchronizable) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func data(forKey key: String, synchronizable: Bool = false) -> Data? {
        var query: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrService:      service,
            kSecAttrAccount:      key,
            kSecReturnData:       true,
            kSecMatchLimit:       kSecMatchLimitOne,
        ]
        if synchronizable {
            query[kSecAttrSynchronizable] = kCFBooleanTrue
        }
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    // MARK: - Delete

    @discardableResult
    static func delete(forKey key: String, synchronizable: Bool = false) -> Bool {
        var query: [CFString: Any] = [
            kSecClass:        kSecClassGenericPassword,
            kSecAttrService:  service,
            kSecAttrAccount:  key,
        ]
        if synchronizable {
            query[kSecAttrSynchronizable] = kCFBooleanTrue
        }
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - Convenience keys

    enum Key {
        static let pinHash       = "fintrack.pinHash"
        static let pinSalt       = "fintrack.pinSalt"
        static let userName      = "fintrack.userName"
        static let useFaceID     = "fintrack.useFaceID"
        static let autoLockSecs  = "fintrack.autoLockSecs"
        static let isSetup       = "fintrack.isSetup"
        // Anti-brute-force: persisted so kill+relaunch cannot reset the counter
        static let failedAttempts = "fintrack.failedAttempts"
        static let blockUntil     = "fintrack.blockUntil"
    }
}
