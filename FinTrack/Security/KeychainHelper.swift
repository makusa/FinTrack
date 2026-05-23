//
//  KeychainHelper.swift
//  FinTrack
//
//  Minimal, strongly-typed wrapper around Security.framework Keychain APIs.
//  All FinTrack secrets are stored under the service "ca.regis.fintrack".
//

import Foundation
import Security

enum KeychainHelper {

    private static let service = "ca.regis.fintrack"

    // MARK: - Write

    @discardableResult
    static func set(_ value: String, forKey key: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        return set(data, forKey: key)
    }

    @discardableResult
    static func set(_ data: Data, forKey key: String) -> Bool {
        // Delete any existing entry first
        delete(forKey: key)

        let query: [CFString: Any] = [
            kSecClass:           kSecClassGenericPassword,
            kSecAttrService:     service,
            kSecAttrAccount:     key,
            kSecValueData:       data,
            // Accessible after first unlock — survives reboots but locked while device is locked
            kSecAttrAccessible:  kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    // MARK: - Read

    static func string(forKey key: String) -> String? {
        guard let data = data(forKey: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func data(forKey key: String) -> Data? {
        let query: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrService:      service,
            kSecAttrAccount:      key,
            kSecReturnData:       true,
            kSecMatchLimit:       kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    // MARK: - Delete

    @discardableResult
    static func delete(forKey key: String) -> Bool {
        let query: [CFString: Any] = [
            kSecClass:        kSecClassGenericPassword,
            kSecAttrService:  service,
            kSecAttrAccount:  key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - Convenience keys

    enum Key {
        static let pinHash      = "fintrack.pinHash"
        static let pinSalt      = "fintrack.pinSalt"
        static let userName     = "fintrack.userName"
        static let useFaceID    = "fintrack.useFaceID"
        static let autoLockSecs = "fintrack.autoLockSecs"
        static let isSetup      = "fintrack.isSetup"
    }
}
