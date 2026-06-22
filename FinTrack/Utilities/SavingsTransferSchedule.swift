//
//  SavingsTransferSchedule.swift
//  FinTrack
//
//  Pure scheduling logic for savings auto-transfers: computes the first transfer
//  date from a chosen frequency + day. No SwiftData dependency (unit-testable).
//

import Foundation

enum SavingsTransferSchedule {
    /// First transfer date on/after `reference`.
    /// - monthly/quarterly/yearly: `day` = day of month (1...31, clamped to month length).
    /// - weekly/biweekly: `day` = weekday (1 = Sunday ... 7 = Saturday, Gregorian).
    /// - daily: `day` ignored.
    static func firstDate(frequency: RecurrenceFrequency,
                          day: Int,
                          onOrAfter reference: Date,
                          calendar: Calendar = .current) -> Date {
        let cal = calendar
        let startRef = cal.startOfDay(for: reference)
        switch frequency {
        case .weekly, .biweekly:
            let targetWeekday  = min(max(day, 1), 7)
            let currentWeekday = cal.component(.weekday, from: startRef)
            let delta = (targetWeekday - currentWeekday + 7) % 7
            return cal.date(byAdding: .day, value: delta, to: startRef) ?? startRef
        case .monthly, .quarterly, .yearly:
            return nextMonthlyDate(dayOfMonth: day, onOrAfter: startRef, calendar: cal)
        case .daily:
            return startRef
        }
    }

    private static func nextMonthlyDate(dayOfMonth: Int, onOrAfter reference: Date, calendar cal: Calendar) -> Date {
        func dateInMonth(of base: Date) -> Date? {
            guard let range = cal.range(of: .day, in: .month, for: base) else { return nil }
            let clampedDay = min(max(dayOfMonth, 1), range.count)
            var comps = cal.dateComponents([.year, .month], from: base)
            comps.day = clampedDay
            return cal.date(from: comps)
        }
        if let candidate = dateInMonth(of: reference), candidate >= reference { return candidate }
        if let nextBase = cal.date(byAdding: .month, value: 1, to: reference),
           let candidate = dateInMonth(of: nextBase) { return candidate }
        return reference
    }

    /// Frequencies offered for savings auto-transfers (subset of RecurrenceFrequency).
    static let offeredFrequencies: [RecurrenceFrequency] = [.weekly, .biweekly, .monthly]

    /// True when this frequency schedules by day-of-week rather than day-of-month.
    static func isWeekdayBased(_ f: RecurrenceFrequency) -> Bool {
        f == .weekly || f == .biweekly
    }
}
