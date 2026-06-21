//
//  CategorizationCore.swift
//  FinTrack
//
//  Pure decision core for transaction categorization. Precedence:
//    1. personal memory  — your past choice beats any generic rule
//    2. built-in dictionary (NAME + MEMO)
//    3. on-device semantic similarity to your own history (phase B, optional)
//    4. nothing          — better blank than wrong
//
//  Returns a category NAME; the SwiftData adapter (TransactionCategorizer)
//  resolves it to the user's actual Category. `eligibleCategoryNames` are the
//  names that exist AND fit the transaction's income/expense side, so any returned
//  suggestion is guaranteed valid and on the correct side. Tested with swiftc.
//

import Foundation

enum CategorizationCore {
    static func decideCategoryName(name: String,
                                   memo: String,
                                   isIncome: Bool,
                                   memory: PayeeMemory,
                                   eligibleCategoryNames: Set<String>,
                                   semantic: ((_ name: String, _ isIncome: Bool, _ eligible: Set<String>) -> String?)? = nil) -> String? {
        // 1) Personal memory (exact normalized payee).
        if let remembered = memory.suggestion(for: name, isIncome: isIncome),
           eligibleCategoryNames.contains(remembered) {
            return remembered
        }
        // 2) Built-in dictionary, on NAME + MEMO.
        let haystack = PayeeNormalizer.normalize(name + " " + memo)
        if let canonical = MerchantDictionary.category(forNormalized: haystack, income: isIncome),
           eligibleCategoryNames.contains(canonical.defaultCategoryName) {
            return canonical.defaultCategoryName
        }
        // 3) On-device semantic similarity to the user's own history (phase B).
        if let semantic, let s = semantic(name, isIncome, eligibleCategoryNames),
           eligibleCategoryNames.contains(s) {
            return s
        }
        // 4) No confident suggestion — better blank than wrong.
        return nil
    }
}
