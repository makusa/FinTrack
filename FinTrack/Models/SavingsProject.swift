//
//  SavingsProject.swift
//  FinTrack
//

import Foundation
import SwiftData

@Model
final class SavingsProject {
    var name: String = ""
    var iconSystemName: String = "star.fill"
    var colorHex: String = "#3478F6"
    var currency: String = "CAD"

    /// Amount already saved (manually maintained, OR derived from linked account).
    var manualCurrentAmount: Decimal = 0
    /// If true, currentAmount is read from the linked account's balance.
    var trackViaAccount: Bool = false

    /// nil = open-ended accumulation (no finish line).
    var targetAmount: Decimal?

    /// Fixed monthly contribution assigned from surplus.
    var monthlyContribution: Decimal = 0

    /// Optional deadline. When set, drives the required contribution calculation.
    var targetDate: Date?

    var notes: String?
    var isActive: Bool = true
    var createdAt: Date = Date.now

    /// Optional savings account (e.g., a dedicated TFSA or FHSA).
    var account: Account?

    // MARK: Computed

    var currentAmount: Decimal {
        trackViaAccount ? (account?.balance ?? manualCurrentAmount) : manualCurrentAmount
    }

    var amountRemaining: Decimal? {
        guard let target = targetAmount else { return nil }
        return max(0, target - currentAmount)
    }

    var progressFraction: Double {
        guard let target = targetAmount, (target as NSDecimalNumber).doubleValue > 0 else { return 0 }
        let ratio = ((currentAmount / target) as NSDecimalNumber).doubleValue
        return min(1, max(0, ratio))
    }

    /// Months until target is reached at current contribution rate.
    var monthsToTarget: Int? {
        guard let remaining = amountRemaining,
              remaining > 0,
              monthlyContribution > 0 else { return nil }
        let months = ((remaining / monthlyContribution) as NSDecimalNumber).doubleValue
        return Int(ceil(months))
    }

    var targetReachDate: Date? {
        guard let months = monthsToTarget else { return nil }
        return Calendar.current.date(byAdding: .month, value: months, to: .now)
    }

    /// Monthly contribution required to hit targetAmount by targetDate.
    var requiredMonthlyForDeadline: Decimal? {
        guard let target = targetAmount, let deadline = targetDate else { return nil }
        let remaining = max(0, target - currentAmount)
        guard (remaining as NSDecimalNumber).doubleValue > 0 else { return 0 }
        let months = Calendar.current.dateComponents([.month], from: .now, to: deadline).month ?? 0
        guard months > 0 else { return remaining }
        return (remaining / Decimal(months)).rounded(scale: 2)
    }

    /// Label summarising the projection status.
    var projectionLabel: String {
        if progressFraction >= 1 { return "Objectif atteint ✓" }
        if let d = targetReachDate {
            let fmt = FormatterCache.datePattern("MMMM yyyy", locale: LanguageManager.shared.locale)
            return "Atteint en \(fmt.string(from: d))"
        }
        if targetAmount == nil {
            let monthlyDouble = (monthlyContribution as NSDecimalNumber).doubleValue
            if monthlyDouble > 0 { return "Accumulation libre · \(monthlyContribution.formatted(asCurrency: currency))" }
        }
        return "Contribution à définir"
    }

    // MARK: Init

    init(
        name: String,
        iconSystemName: String = "star.fill",
        colorHex: String = "#3478F6",
        currency: String = Currencies.default,
        currentAmount: Decimal = 0,
        trackViaAccount: Bool = false,
        targetAmount: Decimal? = nil,
        monthlyContribution: Decimal = 0,
        targetDate: Date? = nil,
        account: Account? = nil,
        notes: String? = nil
    ) {
        self.name = name
        self.iconSystemName = iconSystemName
        self.colorHex = colorHex
        self.currency = currency
        self.manualCurrentAmount = currentAmount
        self.trackViaAccount = trackViaAccount
        self.targetAmount = targetAmount
        self.monthlyContribution = monthlyContribution
        self.targetDate = targetDate
        self.account = account
        self.notes = notes
        self.isActive = true
        self.createdAt = .now
    }
}

private extension Decimal {
    func rounded(scale: Int) -> Decimal {
        var result = Decimal()
        var mutable = self
        NSDecimalRound(&result, &mutable, scale, .plain)
        return result
    }
}
