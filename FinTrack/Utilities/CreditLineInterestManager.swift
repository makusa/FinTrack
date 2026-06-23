//
//  CreditLineInterestManager.swift
//  FinTrack
//
//  Posts credit-line interest on each statement date (configurable per line).
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
        let cal    = Calendar.current
        let today  = cal.startOfDay(for: .now)
        let origin = cal.startOfDay(for: line.lastInterestAccrualDate)

        guard today > origin else { return false }

        // Post ONE interest charge per statement date that has passed (strictly after the
        // last accrual, on or before today). Within each statement period interest is
        // accrued day-by-day; it compounds from one period to the next. The in-progress
        // period (last statement → today) is left un-posted until its statement date.
        var periodStart = origin
        while let statement = nextStatementDate(after: periodStart, statementDay: line.statementDay, cal: cal),
              statement <= today {
            let interest = dailyAccruedInterest(for: line, from: periodStart, to: statement, cal: cal)
            if interest > 0.001 {
                let rounded = (interest * 100).rounded() / 100
                let entry = CreditLineEntry(
                    type: .interestAccrual,
                    amount: Decimal(rounded),
                    date: statement,
                    note: formatDateRange(from: periodStart, to: statement)
                )
                entry.creditLine = line
                context.insert(entry)
            }
            periodStart = statement
        }

        guard periodStart > origin else { return false }   // no statement date reached yet
        line.lastInterestAccrualDate = periodStart
        return true
    }

    /// Next statement date strictly after `date`, on the configured day of month
    /// (clamped to 1–28 so it exists in every month).
    private static func nextStatementDate(after date: Date, statementDay: Int, cal: Calendar) -> Date? {
        let day = max(1, min(statementDay, 28))
        let next = cal.nextDate(after: date,
                                matching: DateComponents(day: day),
                                matchingPolicy: .nextTime,
                                direction: .forward)
        return next.map { cal.startOfDay(for: $0) }
    }

    /// Day-by-day accrued interest over [from, to), taking draws/repayments in the
    /// period into account. The starting balance includes prior posted interest
    /// (entries dated on or before `from`), giving period-to-period compounding.
    private static func dailyAccruedInterest(for line: CreditLine, from: Date, to: Date, cal: Calendar) -> Double {
        let annualRate = (line.annualInterestRate / 100 as NSDecimalNumber).doubleValue
        let dailyRate: Double
        switch line.compounding {
        case .daily:
            dailyRate = annualRate / 365.0
        case .monthly:
            let monthlyRate = annualRate / 12.0
            dailyRate = pow(1.0 + monthlyRate, 1.0 / 30.0) - 1.0
        }

        var runningBalance: Double = {
            let all = (line.entries ?? [])
                .filter { $0.date <= from }
                .reduce(Decimal(0)) { $0 + $1.signedAmount }
            return max(0, (all as NSDecimalNumber).doubleValue)
        }()

        let movements = (line.entries ?? [])
            .filter { $0.type != .interestAccrual && $0.date > from && $0.date < to }
            .sorted { $0.date < $1.date }

        var total = 0.0
        var day = cal.startOfDay(for: from)
        let end = cal.startOfDay(for: to)
        while day < end {
            for entry in movements where cal.isDate(entry.date, inSameDayAs: day) {
                runningBalance = max(0, runningBalance + (entry.signedAmount as NSDecimalNumber).doubleValue)
            }
            if runningBalance > 0 { total += runningBalance * dailyRate }
            day = cal.date(byAdding: .day, value: 1, to: day)!
        }
        return total
    }


    private static func formatDateRange(from start: Date, to end: Date) -> String {
        let fmt = FormatterCache.datePattern("d MMM", locale: LanguageManager.shared.locale)
        return "\(fmt.string(from: start)) → \(fmt.string(from: end))"
    }
}
