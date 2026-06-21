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
    }

    /// Suggested category for an incoming transaction, or nil to leave it blank.
    func suggest(name: String?, memo: String = "", type: TransactionType) -> Category? {
        let eligible = (type == .income) ? eligibleIncome : eligibleExpense
        guard let chosen = CategorizationCore.decideCategoryName(
            name: name ?? "", memo: memo, isIncome: type == .income,
            memory: memory, eligibleCategoryNames: eligible) else { return nil }
        return categoriesByName[chosen]
    }
}
