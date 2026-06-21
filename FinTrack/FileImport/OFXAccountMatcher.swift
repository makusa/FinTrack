//
//  OFXAccountMatcher.swift
//  FinTrack
//
//  Suggests which FinTrack account a parsed statement belongs to. Pure and
//  SwiftData-free (operates on lightweight descriptors) so it is unit-testable.
//  The matcher only SUGGESTS — the user always confirms in the import preview.
//

import Foundation

/// SwiftData-free view of an account, for matching.
struct ImportAccountDescriptor: Equatable {
    let uuid: String
    let currency: String
    let typeRaw: String      // AccountType.rawValue
}

struct AccountSuggestion: Equatable {
    enum Confidence: Equatable {
        case remembered   // this exact bank account was mapped before → auto
        case strong       // unique currency (+ type) match → pre-select
        case weak         // ambiguous / currency-only → pre-select but confirm
        case none         // nothing fits → user must choose
    }
    let accountUuid: String?
    let confidence: Confidence

    static let unresolved = AccountSuggestion(accountUuid: nil, confidence: .none)
}

enum OFXAccountMatcher {

    /// Strongest signal first: remembered mapping → currency + ACCTTYPE → nothing.
    static func suggest(statement: OFXStatement,
                        accounts: [ImportAccountDescriptor],
                        remembered: [String: String]) -> AccountSuggestion {
        guard !accounts.isEmpty else { return .unresolved }
        let uuids = Set(accounts.map { $0.uuid })

        // 1) Remembered fingerprint (only if that account still exists).
        let fp = ImportAccountMap.fingerprint(bankId: statement.bankId, acctId: statement.accountId)
        if !fp.isEmpty, let mapped = remembered[fp], uuids.contains(mapped) {
            return AccountSuggestion(accountUuid: mapped, confidence: .remembered)
        }

        // 2) Currency filter (only when the statement declares one).
        let byCurrency: [ImportAccountDescriptor]
        if let cur = statement.currency, !cur.isEmpty {
            byCurrency = accounts.filter { $0.currency == cur }
        } else {
            byCurrency = accounts
        }
        guard !byCurrency.isEmpty else { return .unresolved }

        // 2b) Prefer ACCTTYPE → AccountType.
        if let expected = expectedTypeRaw(for: statement.accountType) {
            let typed = byCurrency.filter { $0.typeRaw == expected }
            if typed.count == 1 { return AccountSuggestion(accountUuid: typed[0].uuid, confidence: .strong) }
            if typed.count > 1  { return AccountSuggestion(accountUuid: typed[0].uuid, confidence: .weak) }
        }

        // 2c) No type match: fall back to the currency candidates.
        if byCurrency.count == 1 {
            return AccountSuggestion(accountUuid: byCurrency[0].uuid, confidence: .strong)
        }
        return AccountSuggestion(accountUuid: byCurrency[0].uuid, confidence: .weak)
    }

    /// OFX ACCTTYPE → AccountType.rawValue. Conservative; unknown → nil.
    static func expectedTypeRaw(for acctType: String?) -> String? {
        switch acctType?.uppercased() {
        case "CHECKING":                 return "checking"
        case "SAVINGS":                  return "savings"
        case "MONEYMRKT", "CD":          return "savings"
        case "CREDITLINE", "CREDITCARD": return "credit"
        default:                         return nil
        }
    }
}
