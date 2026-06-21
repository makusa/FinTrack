//
//  TransactionCategorizer.swift
//  FinTrack
//
//  SwiftData-facing categorizer. Build once per import from the user's categories
//  and existing transactions, then call `suggest` per incoming transaction. The
//  decision logic lives in the pure CategorizationCore; this is just resolution.
//

import Foundation
import SwiftData

struct TransactionCategorizer {
    private let memory: PayeeMemory
    private let categoriesByName: [String: Category]
    private let eligibleIncome: Set<String>
    private let eligibleExpense: Set<String>
    private let semanticIndex: SemanticIndex
    private static let minSimilarity = 0.82   // conservateur (à ajuster sur appareil)

    init(categories: [Category], history: [Transaction]) {
        categoriesByName = Dictionary(categories.map { ($0.name, $0) },
                                      uniquingKeysWith: { first, _ in first })
        eligibleExpense = Set(categories.filter { $0.matches(.expense) && !$0.isHidden }.map(\.name))
        eligibleIncome  = Set(categories.filter { $0.matches(.income)  && !$0.isHidden }.map(\.name))

        let entries: [(payee: String, categoryKey: String, isIncome: Bool)] = history.compactMap { tx in
            guard let category = tx.category, let payee = tx.payee, !payee.isEmpty else { return nil }
            return (payee, category.name, tx.type == .income)
        }
        memory = PayeeMemory(history: entries)
        semanticIndex = SemanticIndex(history: entries)
    }

    /// Suggested category for an incoming transaction, or nil to leave it blank.
    func suggest(name: String?, memo: String = "", type: TransactionType) -> Category? {
        let eligible = (type == .income) ? eligibleIncome : eligibleExpense
        let index = semanticIndex
        let minSim = Self.minSimilarity
        let semantic: (String, Bool, Set<String>) -> String? = { n, inc, elig in
            index.suggestion(name: n, isIncome: inc, eligible: elig, minSimilarity: minSim)
        }
        guard let chosen = CategorizationCore.decideCategoryName(
            name: name ?? "", memo: memo, isIncome: type == .income,
            memory: memory, eligibleCategoryNames: eligible, semantic: semantic) else { return nil }
        return categoriesByName[chosen]
    }
}
