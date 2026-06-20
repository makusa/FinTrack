//
//  CreditCardProfile.swift
//  FinTrack
//
//  Budget-management metadata for a credit-card Account (type == .credit).
//  Linked 1:1 to an Account. The Account owns the transactions and the
//  balance; this profile adds the statement cycle, limit, interest rate and
//  minimum-payment rule needed for budgeting a card.
//
//  Sign convention — a credit card is a LIABILITY. Purchases are .expense
//  (sign -1), so the owning Account's balance is <= 0 when money is owed.
//  "Amount owed" for display is therefore max(0, -account.balance), and a
//  card payment is naturally a transfer from a bank account to the card.
//
//  Reuses MinimumPaymentType (defined in CreditLine.swift).
//

import Foundation
import SwiftData

// MARK: - Card network

enum CardNetwork: String, CaseIterable, Identifiable {
    case visa
    case mastercard
    case amex
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .visa:       return LanguageManager.shared["card.network.visa"]
        case .mastercard: return LanguageManager.shared["card.network.mastercard"]
        case .amex:       return LanguageManager.shared["card.network.amex"]
        case .other:      return LanguageManager.shared["card.network.other"]
        }
    }
}

// MARK: - Model

@Model
final class CreditCardProfile {
    // Limit & identification
    var creditLimit: Decimal = 0
    var cardNetworkRaw: String = CardNetwork.other.rawValue
    var lastFour: String?                    // 4-digit mask; optional

    // Statement cycle (1...31; clamped to month length at compute time)
    var statementDayOfMonth: Int = 1         // day the statement closes
    var paymentDueDayOfMonth: Int = 21       // day payment is due

    // Interest (annual %, e.g. 20.99)
    var purchaseAPR: Decimal = 0
    var cashAdvanceAPR: Decimal?             // optional; nil = not tracked

    // Minimum payment — reuses the shared MinimumPaymentType enum
    var minimumPaymentTypeRaw: String = MinimumPaymentType.percentBalance.rawValue
    var minimumPaymentValue: Decimal = 0     // percent OR fixed amount
    var minimumPaymentFloor: Decimal = 10    // issuer floor (CAD $10 typical)

    // Reminders — fields stored now; scheduling wired in a later increment
    var notificationEnabled: Bool = false
    var notificationDaysBefore: Int = 3

    var createdAt: Date = Date.now

    // 1:1 link; inverse + cascade declared on Account.creditCardProfile.
    var account: Account?

    // MARK: Accessors

    var cardNetwork: CardNetwork {
        get { CardNetwork(rawValue: cardNetworkRaw) ?? .other }
        set { cardNetworkRaw = newValue.rawValue }
    }

    var minimumPaymentType: MinimumPaymentType {
        get { MinimumPaymentType(rawValue: minimumPaymentTypeRaw) ?? .percentBalance }
        set { minimumPaymentTypeRaw = newValue.rawValue }
    }

    // MARK: Owed / availability (HIGH CONFIDENCE)

    /// Real-time amount owed, shown as a positive number (liability).
    var amountOwed: Decimal {
        max(0, -(account?.balance ?? 0))
    }

    /// Credit still available to spend.
    var availableCredit: Decimal {
        max(0, creditLimit - amountOwed)
    }

    /// Utilisation ratio (0...1) = owed / limit. Key budgeting + credit signal.
    var utilisationFraction: Double {
        let limit = (creditLimit as NSDecimalNumber).doubleValue
        guard limit > 0 else { return 0 }
        let owed = (amountOwed as NSDecimalNumber).doubleValue
        return min(1, max(0, owed / limit))
    }

    // MARK: Interest & minimum payment (ESTIMATES — label as such in UI)

    /// Rough monthly interest IF a balance is carried past the due date.
    /// Real interest uses the average daily balance and grace-period rules;
    /// this is a conservative display estimate only.
    var monthlyInterestEstimate: Decimal {
        guard amountOwed > 0 else { return 0 }
        return amountOwed * purchaseAPR / 100 / 12
    }

    /// Estimated minimum payment due this cycle.
    var estimatedMinimumPayment: Decimal {
        guard amountOwed > 0 else { return 0 }
        switch minimumPaymentType {
        case .interestOnly:
            return max(minimumPaymentFloor, monthlyInterestEstimate)
        case .percentBalance:
            let pct = minimumPaymentValue / 100
            return min(amountOwed, max(minimumPaymentFloor, amountOwed * pct))
        case .fixedAmount:
            return min(amountOwed, minimumPaymentValue)
        }
    }

    // MARK: Statement cycle dates (HIGH CONFIDENCE)

    /// Next date on/after `ref` whose day-of-month equals `day`, clamping the
    /// day to the month's length (e.g. 31 → 28/29 in February).
    private static func nextOccurrence(ofDay day: Int, onOrAfter ref: Date,
                                       calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: ref)
        for monthOffset in 0...12 {
            guard let monthDate = calendar.date(byAdding: .month, value: monthOffset, to: start),
                  let range = calendar.range(of: .day, in: .month, for: monthDate) else { continue }
            let clampedDay = min(max(1, day), range.count)
            var comps = calendar.dateComponents([.year, .month], from: monthDate)
            comps.day = clampedDay
            if let candidate = calendar.date(from: comps), candidate >= start {
                return candidate
            }
        }
        return start
    }

    /// Next statement closing date on/after `ref`.
    func nextStatementCloseDate(from ref: Date = .now) -> Date {
        Self.nextOccurrence(ofDay: statementDayOfMonth, onOrAfter: ref)
    }

    /// Next payment due date on/after `ref`.
    func nextPaymentDueDate(from ref: Date = .now) -> Date {
        Self.nextOccurrence(ofDay: paymentDueDayOfMonth, onOrAfter: ref)
    }

    /// Whole days from `ref` until the next payment due date (>= 0).
    func daysUntilPaymentDue(from ref: Date = .now) -> Int {
        let cal = Calendar.current
        let due = nextPaymentDueDate(from: ref)
        return cal.dateComponents([.day], from: cal.startOfDay(for: ref), to: due).day ?? 0
    }

    // TODO (reconciliation increment): statementBalance — the amount owed as of
    // the last statement close. Requires summing transactions up to that date,
    // which ties into posted-vs-pending transaction status.

    // MARK: Init

    init(
        creditLimit: Decimal,
        cardNetwork: CardNetwork = .other,
        lastFour: String? = nil,
        statementDayOfMonth: Int = 1,
        paymentDueDayOfMonth: Int = 21,
        purchaseAPR: Decimal = 0,
        cashAdvanceAPR: Decimal? = nil,
        minimumPaymentType: MinimumPaymentType = .percentBalance,
        minimumPaymentValue: Decimal = 0,
        minimumPaymentFloor: Decimal = 10
    ) {
        self.creditLimit = creditLimit
        self.cardNetworkRaw = cardNetwork.rawValue
        self.lastFour = lastFour
        self.statementDayOfMonth = statementDayOfMonth
        self.paymentDueDayOfMonth = paymentDueDayOfMonth
        self.purchaseAPR = purchaseAPR
        self.cashAdvanceAPR = cashAdvanceAPR
        self.minimumPaymentTypeRaw = minimumPaymentType.rawValue
        self.minimumPaymentValue = minimumPaymentValue
        self.minimumPaymentFloor = minimumPaymentFloor
        self.createdAt = .now
    }
}
