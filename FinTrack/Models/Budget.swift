//
//  Budget.swift
//  FinTrack
//
//  A spending budget tied to a category (or to all expenses if category is nil).
//  Spending is computed at query time from Transaction records — the budget
//  stores only the limit and metadata.
//

import Foundation
import SwiftData

// MARK: - Budget period

enum BudgetPeriod: String, CaseIterable, Identifiable {
    case weekly    = "weekly"
    case monthly   = "monthly"
    case yearly    = "yearly"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .weekly:  return LanguageManager.shared["budget.period.weekly"]
        case .monthly: return LanguageManager.shared["budget.period.monthly"]
        case .yearly:  return LanguageManager.shared["budget.period.yearly"]
        }
    }

    var shortLabel: String {
        switch self {
        case .weekly:  return LanguageManager.shared["budget.period.weekly.short"]
        case .monthly: return LanguageManager.shared["budget.period.monthly.short"]
        case .yearly:  return LanguageManager.shared["budget.period.yearly.short"]
        }
    }

    /// Start of the current period containing `date`.
    func periodStart(for date: Date = .now) -> Date {
        let cal = Calendar.current
        switch self {
        case .weekly:
            return cal.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        case .monthly:
            return cal.dateInterval(of: .month, for: date)?.start ?? date
        case .yearly:
            return cal.dateInterval(of: .year, for: date)?.start ?? date
        }
    }

    /// End of the current period (exclusive).
    func periodEnd(for date: Date = .now) -> Date {
        let cal = Calendar.current
        switch self {
        case .weekly:
            return cal.date(byAdding: .weekOfYear, value: 1, to: periodStart(for: date)) ?? date
        case .monthly:
            return cal.date(byAdding: .month, value: 1, to: periodStart(for: date)) ?? date
        case .yearly:
            return cal.date(byAdding: .year, value: 1, to: periodStart(for: date)) ?? date
        }
    }

    /// Human-readable label for the current period window.
    func currentPeriodLabel() -> String {
        let start = periodStart()
        let end   = Calendar.current.date(byAdding: .day, value: -1, to: periodEnd()) ?? periodEnd()
        let locale = LanguageManager.shared.locale
        let fmt   = DateFormatter()
        switch self {
        case .weekly:
            fmt.locale = locale
            fmt.dateFormat = "d MMM"
            return "\(fmt.string(from: start)) – \(fmt.string(from: end))"
        case .monthly:
            fmt.locale = locale
            fmt.dateFormat = "MMMM yyyy"
            return fmt.string(from: start).capitalized
        case .yearly:
            fmt.locale = locale
            fmt.dateFormat = "yyyy"
            return fmt.string(from: start)
        }
    }
}

// MARK: - Model

@Model
final class Budget {
    var name: String = ""
    var limitAmount: Decimal = 0
    var currency: String = "CAD"
    var periodRaw: String = BudgetPeriod.monthly.rawValue
    var colorHex: String = "#3478F6"
    var iconSystemName: String = "cart.fill"
    var isActive: Bool = true
    var notes: String? = nil
    var createdAt: Date = Date.now

    /// Nil = applies to ALL expense categories (global spending budget).
    @Relationship(deleteRule: .nullify, inverse: \Category.budgets)
    var category: Category? = nil

    var period: BudgetPeriod {
        get { BudgetPeriod(rawValue: periodRaw) ?? .monthly }
        set { periodRaw = newValue.rawValue }
    }

    init(
        name: String,
        limitAmount: Decimal,
        currency: String,
        period: BudgetPeriod,
        colorHex: String = "#3478F6",
        iconSystemName: String = "cart.fill",
        category: Category? = nil,
        notes: String? = nil
    ) {
        self.name          = name
        self.limitAmount   = limitAmount
        self.currency      = currency
        self.periodRaw     = period.rawValue
        self.colorHex      = colorHex
        self.iconSystemName = iconSystemName
        self.category      = category
        self.notes         = notes
        self.isActive      = true
        self.createdAt     = .now
    }
}

// MARK: - BudgetStatus (computed, not stored)

struct BudgetStatus {
    let budget: Budget
    let spent: Decimal
    let remaining: Decimal
    let fraction: Double          // 0…1+  (can exceed 1 when over budget)
    let isOverBudget: Bool
    let isNearLimit: Bool         // > 80 %

    init(budget: Budget, spent: Decimal) {
        self.budget   = budget
        self.spent    = spent
        let limit     = budget.limitAmount
        self.remaining   = limit - spent
        let dbl       = limit > 0
            ? ((spent as NSDecimalNumber).doubleValue / (limit as NSDecimalNumber).doubleValue)
            : 0
        self.fraction    = dbl
        self.isOverBudget = spent > limit
        self.isNearLimit  = dbl >= 0.8 && dbl < 1.0
    }

    var progressColor: Color {
        if isOverBudget  { return .red }
        if isNearLimit   { return .orange }
        return .green
    }
}

import SwiftUI  // for Color in BudgetStatus

// MARK: - BudgetCalculator

/// Pure functions — no SwiftData queries inside. Callers pass transactions.
enum BudgetCalculator {

    /// Returns the total expense amount for a budget during its current period.
    static func spent(
        for budget: Budget,
        in transactions: [Transaction]
    ) -> Decimal {
        let start = budget.period.periodStart()
        let end   = budget.period.periodEnd()

        return transactions
            .filter { tx in
                guard tx.type == .expense else { return false }
                guard tx.date >= start && tx.date < end else { return false }
                guard tx.account?.currency == budget.currency else { return false }
                if let cat = budget.category {
                    return tx.category?.persistentModelID == cat.persistentModelID
                }
                return true   // global budget: all expenses in currency
            }
            .reduce(Decimal(0)) { $0 + $1.amount }
    }

    /// Historical spending per period for sparkline / trend.
    /// Returns up to `count` past periods (most recent last).
    static func history(
        for budget: Budget,
        in transactions: [Transaction],
        count: Int = 6
    ) -> [Decimal] {
        let cal = Calendar.current
        var results: [Decimal] = []
        var offset = count - 1

        while offset >= 0 {
            let anchor: Date
            switch budget.period {
            case .weekly:
                anchor = cal.date(byAdding: .weekOfYear, value: -offset, to: .now) ?? .now
            case .monthly:
                anchor = cal.date(byAdding: .month,      value: -offset, to: .now) ?? .now
            case .yearly:
                anchor = cal.date(byAdding: .year,       value: -offset, to: .now) ?? .now
            }

            let start = budget.period.periodStart(for: anchor)
            let end   = budget.period.periodEnd(for: anchor)

            let total = transactions
                .filter { tx in
                    guard tx.type == .expense else { return false }
                    guard tx.date >= start && tx.date < end else { return false }
                    guard tx.account?.currency == budget.currency else { return false }
                    if let cat = budget.category {
                        return tx.category?.persistentModelID == cat.persistentModelID
                    }
                    return true
                }
                .reduce(Decimal(0)) { $0 + $1.amount }

            results.append(total)
            offset -= 1
        }
        return results
    }
}
