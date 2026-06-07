//
//  CreditLineInterestManager.swift
//  FinTrack
//
//  Accrues daily interest on all active credit lines at app launch.
//  Interest is computed day-by-day, taking into account any draws or
//  repayments that occurred between the last accrual date and today.
//  A single CreditLineEntry of type .interestAccrual is inserted per line.
//

import Foundation
import SwiftData

enum CreditLineInterestManager {

    // MARK: - Public API

    static func applyPending(context: ModelContext) {
        let descriptor = FetchDescriptor<CreditLine>(
            predicate: #Predicate { $0.isActive }
        )
        let lines = (try? context.fetch(descriptor)) ?? []

        var didChange = false
        for line in lines {
            if accrueInterest(for: line, context: context) { didChange = true }
        }
        if didChange { try? context.save() }
    }

    // MARK: - Per-line accrual

    @discardableResult
    private static func accrueInterest(for line: CreditLine, context: ModelContext) -> Bool {
        let cal   = Calendar.current
        let today = cal.startOfDay(for: .now)
        let start = cal.startOfDay(for: line.lastInterestAccrualDate)

        guard today > start else { return false }   // already accrued today

        let annualRate = (line.annualInterestRate / 100 as NSDecimalNumber).doubleValue

        // Daily rate depends on compounding convention
        let dailyRate: Double
        switch line.compounding {
        case .daily:
            dailyRate = annualRate / 365.0
        case .monthly:
            // Convert monthly rate to daily equivalent
            let monthlyRate = annualRate / 12.0
            dailyRate = pow(1.0 + monthlyRate, 1.0 / 30.0) - 1.0
        }

        // Collect all entries after the last accrual date, sorted by date.
        // These entries (draws/repayments) change the balance mid-period.
        let movementsSinceAccrual = line.entries
            .filter { $0.type != .interestAccrual && $0.date > line.lastInterestAccrualDate }
            .sorted { $0.date < $1.date }

        // Balance at the start of the accrual period
        var runningBalance: Double = {
            let all = line.entries
                .filter { $0.date <= line.lastInterestAccrualDate }
                .reduce(Decimal(0)) { $0 + $1.signedAmount }
            return max(0, (all as NSDecimalNumber).doubleValue)
        }()

        var totalInterest: Double = 0.0
        var currentDay = start

        while currentDay < today {
            let nextDay = cal.date(byAdding: .day, value: 1, to: currentDay)!

            // Apply movements that occurred on currentDay
            for entry in movementsSinceAccrual
            where cal.isDate(entry.date, inSameDayAs: currentDay) {
                let signed = (entry.signedAmount as NSDecimalNumber).doubleValue
                runningBalance = max(0, runningBalance + signed)
            }

            // Accrue interest on the balance at end of currentDay
            if runningBalance > 0 {
                totalInterest += runningBalance * dailyRate
            }

            currentDay = nextDay
        }

        guard totalInterest > 0.001 else {
            // Update the date even if no interest (zero-balance period)
            line.lastInterestAccrualDate = today
            return false
        }

        // Round to 2 decimal places (cents)
        let rounded = (totalInterest * 100).rounded() / 100
        let entry = CreditLineEntry(
            type: .interestAccrual,
            amount: Decimal(rounded),
            date: today,
            note: "Intérêts courus (\(line.entries.count > 0 ? formatDateRange(from: start, to: today) : ""))"
        )
        entry.creditLine = line
        context.insert(entry)

        line.lastInterestAccrualDate = today
        return true
    }

    private static func formatDateRange(from start: Date, to end: Date) -> String {
        let fmt = FormatterCache.datePattern("d MMM", locale: LanguageManager.shared.locale)
        return "\(fmt.string(from: start)) → \(fmt.string(from: end))"
    }
}
