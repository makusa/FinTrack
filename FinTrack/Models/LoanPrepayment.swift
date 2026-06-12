//
//  LoanPrepayment.swift
//  FinTrack
//
//  Represents a prepayment on a loan — either a one-time lump sum or a
//  recurring extra payment applied on top of the regular amortization schedule.
//
//  Prepayments reduce the principal balance and therefore shorten the loan
//  duration and decrease total interest paid.
//

import Foundation
import SwiftData

// MARK: - Model

@Model
final class LoanPrepayment {

    // MARK: Stored properties

    var amount: Decimal = 0       // always positive; extra principal applied each occurrence
    var startDate: Date = Date.now    // for one-time: the exact payment date; for recurring: first occurrence
    var isRecurring: Bool = false
    var frequencyRaw: String?    // RecurrenceFrequency.rawValue — nil for one-time
    var endDate: Date?           // optional stop date for recurring prepayments
    var note: String?
    var createdAt: Date = Date.now
    // MARK: Notification settings
    var notificationEnabled: Bool = false
    var notificationDaysBefore: Int = 3

    /// Source account debited for each prepayment occurrence.
    /// When set, a Transaction is automatically generated to reflect the cash outflow.
    @Relationship(deleteRule: .nullify, inverse: \Account.loanPrepayments)
    var account: Account? = nil

    /// Tracks which occurrences have already been posted as Transactions.
    /// For one-time: nil = not yet posted, .distantFuture = posted.
    /// For recurring: the next date to post (advances after each run).
    var nextPostDate: Date? = nil

    var loan: Loan?

    // MARK: Computed accessor

    var frequency: RecurrenceFrequency? {
        get { frequencyRaw.flatMap { RecurrenceFrequency(rawValue: $0) } }
        set { frequencyRaw = newValue?.rawValue }
    }

    // MARK: Init

    init(
        amount: Decimal,
        startDate: Date,
        isRecurring: Bool,
        frequency: RecurrenceFrequency? = nil,
        endDate: Date? = nil,
        note: String? = nil
    ) {
        self.amount = amount
        self.startDate = startDate
        self.isRecurring = isRecurring
        self.frequencyRaw = frequency?.rawValue
        self.endDate = endDate
        self.note = note
        self.createdAt = .now
    }
}

// MARK: - PrepaymentInfo (pure value type used by LoanCalculator)

/// A concrete (date, amount) prepayment occurrence, independent of SwiftData.
struct PrepaymentInfo {
    let amount: Double
    let date: Date
}
