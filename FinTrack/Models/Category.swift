//
//  Category.swift
//  FinTrack
//
//  Categorization for transactions. Both income and expense categories live
//  here, distinguished by `applicability`.
//

import Foundation
import SwiftData

enum CategoryApplicability: String, CaseIterable, Identifiable {
    case income
    case expense
    case both

    var id: String { rawValue }
}

@Model
final class Category {
    var name: String = ""
    /// Localization key for system categories (e.g. "category.grocery").
    /// nil = user-created category — display `name` directly.
    var localizationKey: String? = nil
    var iconSystemName: String = "tag.fill"
    var colorHex: String = "#3478F6"
    var applicabilityRaw: String = CategoryApplicability.expense.rawValue
    var isSystem: Bool = false    // built-in categories cannot be deleted, only hidden
    var isHidden: Bool = false
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .nullify, inverse: \Transaction.category)
    var transactions: [Transaction] = []

    // CloudKit inverse requirements (see Account.swift for rationale).
    @Relationship(deleteRule: .nullify, inverse: \RecurringTransaction.category)
    var recurringRules: [RecurringTransaction] = []

    @Relationship(deleteRule: .nullify, inverse: \Budget.category)
    var budgets: [Budget] = []

    /// Returns the translated name for system categories, or `name` for user-created ones.
    var localizedName: String {
        guard let key = localizationKey, !key.isEmpty else { return name }
        let translated = LanguageManager.shared[key]
        return translated.isEmpty ? name : translated
    }

    var applicability: CategoryApplicability {
        get { CategoryApplicability(rawValue: applicabilityRaw) ?? .expense }
        set { applicabilityRaw = newValue.rawValue }
    }

    init(
        name: String,
        localizationKey: String? = nil,
        iconSystemName: String,
        colorHex: String,
        applicability: CategoryApplicability,
        isSystem: Bool = false
    ) {
        self.name = name
        self.localizationKey = localizationKey
        self.iconSystemName = iconSystemName
        self.colorHex = colorHex
        self.applicabilityRaw = applicability.rawValue
        self.isSystem = isSystem
        self.isHidden = false
        self.createdAt = .now
    }

    /// Returns true if this category is appropriate for the given transaction type.
    func matches(_ txType: TransactionType) -> Bool {
        switch applicability {
        case .both:    return true
        case .income:  return txType == .income
        case .expense: return txType == .expense
        }
    }
}
