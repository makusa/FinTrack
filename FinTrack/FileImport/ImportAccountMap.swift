//
//  ImportAccountMap.swift
//  FinTrack
//
//  Remembers which FinTrack account a given bank account maps to, so repeat
//  imports auto-target the right account. Stores ONLY a one-way SHA-256 hash of
//  BANKID|ACCTID — never the account number in clear. Local (UserDefaults).
//

import Foundation
import CryptoKit

enum ImportAccountMap {
    private static let key = "fintrack.import.accountMap_v1"

    /// fingerprint → Account.uuid
    static func remembered() -> [String: String] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let map = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return map
    }

    static func record(fingerprint: String, accountUuid: String) {
        guard !fingerprint.isEmpty else { return }
        var map = remembered()
        map[fingerprint] = accountUuid
        if let data = try? JSONEncoder().encode(map) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// One-way, cross-launch-stable fingerprint of the bank account identity.
    /// Returns "" when there's no id to fingerprint (no basis to remember).
    static func fingerprint(bankId: String?, acctId: String?) -> String {
        let bank = bankId?.trimmingCharacters(in: .whitespaces) ?? ""
        let acct = acctId?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !(bank.isEmpty && acct.isEmpty) else { return "" }
        let digest = SHA256.hash(data: Data("\(bank)|\(acct)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
