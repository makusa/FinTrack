//
//  CreditLine.swift
//  FinTrack
//
//  A revolving line of credit (marge de crédit). Unlike a Loan, the balance
//  is not fixed — the holder can draw and repay freely. Interest accrues daily
//  on the outstanding balance.
//
//  Balance is event-sourced from CreditLineEntry records (draws, repayments,
//  interest accruals), matching the philosophy used for Account.balance.
//

import Foundation
import SwiftData

// MARK: - Entry type

enum CreditLineEntryType: String, CaseIterable, Identifiable {
    case draw             // Retrait (increases balance owed)
    case repayment        // Remboursement (decreases balance owed)
    case interestAccrual  // Intérêts courus (increases balance owed)

    var id: String { rawValue }

    var label: String {
        switch self {
        case .draw:            return LanguageManager.shared["cl.entry.draw"]
        case .repayment:       return LanguageManager.shared["cl.entry.repayment"]
        case .interestAccrual: return LanguageManager.shared["cl.entry.interest"]
        }
    }

    var iconSystemName: String {
        switch self {
        case .draw:            return "arrow.down.circle.fill"
        case .repayment:       return "arrow.up.circle.fill"
        case .interestAccrual: return "percent"
        }
    }

    var color: String {
        switch self {
        case .draw:            return "#FF3B30"
        case .repayment:       return "#34C759"
        case .interestAccrual: return "#FF9500"
        }
    }
}

// MARK: - Entry model

@Model
final class CreditLineEntry {
    var typeRaw: String = CreditLineEntryType.draw.rawValue
    var amount: Decimal = 0          // always positive
    var date: Date = Date.now
    var note: String = ""
    var createdAt: Date = Date.now

    /// Account debited (repayment) or credited (draw) when this entry is saved.
    /// nil = entry not linked to an account (e.g. auto-generated interest accruals).
    @Relationship(deleteRule: .nullify, inverse: \Account.creditLineEntries)
    var account: Account? = nil

    var creditLine: CreditLine?

    var type: CreditLineEntryType {
        get { CreditLineEntryType(rawValue: typeRaw) ?? .draw }
        set { typeRaw = newValue.rawValue }
    }

    /// Effect on the outstanding balance.
    /// Draws and interest increase what is owed; repayments decrease it.
    var signedAmount: Decimal {
        switch type {
        case .draw, .interestAccrual: return  amount
        case .repayment:              return -amount
        }
    }

    init(type: CreditLineEntryType, amount: Decimal, date: Date = .now, note: String = "") {
        self.typeRaw  = type.rawValue
        self.amount   = amount
        self.date     = date
        self.note     = note
        self.createdAt = .now
    }
}

// MARK: - Compounding convention

enum CreditLineCompounding: String, CaseIterable, Identifiable {
    case daily   // Quotidienne (most Canadian LOCs)
    case monthly // Mensuelle

    var id: String { rawValue }

    var label: String {
        switch self {
        case .daily:   return LanguageManager.shared["cl.compound.daily"]
        case .monthly: return LanguageManager.shared["cl.compound.monthly"]
        }
    }
}

// MARK: - Minimum payment rule

enum MinimumPaymentType: String, CaseIterable, Identifiable {
    case interestOnly   // Pay only accrued interest each month
    case percentBalance // % of outstanding balance (e.g. 2 %)
    case fixedAmount    // Fixed dollar amount

    var id: String { rawValue }

    var label: String {
        switch self {
        case .interestOnly:   return LanguageManager.shared["cl.minType.interestOnly"]
        case .percentBalance: return LanguageManager.shared["cl.minType.percent"]
        case .fixedAmount:    return LanguageManager.shared["cl.minType.fixed"]
        }
    }
}

// MARK: - Main model

@Model
final class CreditLine {
    var name: String = ""
    var lenderName: String = ""
    var currency: String = "CAD"
    var creditLimit: Decimal = 0
    var annualInterestRate: Decimal = 0    // percent, e.g. 7.2
    var compoundingRaw: String = CreditLineCompounding.daily.rawValue
    var minimumPaymentTypeRaw: String = MinimumPaymentType.interestOnly.rawValue
    var minimumPaymentValue: Decimal = 0  // percent OR fixed amount, ignored for interestOnly
    var lastInterestAccrualDate: Date = Date.now
    var isActive: Bool = true
    // MARK: Notification settings
    var notificationEnabled: Bool = false
    var notificationDaysBefore: Int = 3


    var notes: String?
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .nullify, inverse: \Account.creditLines)
    var account: Account?   // bank account debited for repayments

    @Relationship(deleteRule: .cascade, inverse: \CreditLineEntry.creditLine)
    var entries: [CreditLineEntry]? = []

    /// Recurring rule generating this credit line's repayments (deleted with it).
    @Relationship(deleteRule: .cascade, inverse: \RecurringTransaction.creditLine)
    var paymentRule: RecurringTransaction?

    // MARK: Accessors

    var compounding: CreditLineCompounding {
        get { CreditLineCompounding(rawValue: compoundingRaw) ?? .daily }
        set { compoundingRaw = newValue.rawValue }
    }

    var minimumPaymentType: MinimumPaymentType {
        get { MinimumPaymentType(rawValue: minimumPaymentTypeRaw) ?? .interestOnly }
        set { minimumPaymentTypeRaw = newValue.rawValue }
    }

    // MARK: Balance

    /// Current outstanding balance (amount owed). Always >= 0.
    var currentBalance: Decimal {
        max(0, (entries ?? []).reduce(Decimal(0)) { $0 + $1.signedAmount })
    }

    /// Available credit remaining.
    var availableCredit: Decimal {
        max(0, creditLimit - currentBalance)
    }

    /// Utilisation ratio (0–1).
    var utilisationFraction: Double {
        guard (creditLimit as NSDecimalNumber).doubleValue > 0 else { return 0 }
        return min(1, ((currentBalance / creditLimit) as NSDecimalNumber).doubleValue)
    }

    // MARK: Minimum payment calculation

    /// Estimated minimum payment due this month.
    var estimatedMinimumPayment: Decimal {
        switch minimumPaymentType {
        case .interestOnly:
            return monthlyInterestEstimate
        case .percentBalance:
            let pct = minimumPaymentValue / 100
            return max(Decimal(10), currentBalance * pct)  // floor at $10
        case .fixedAmount:
            return minimumPaymentValue
        }
    }

    var monthlyInterestEstimate: Decimal {
        let balance = currentBalance
        let rate = annualInterestRate / 100
        switch compounding {
        case .daily:
            return balance * rate / Decimal(365) * Decimal(30)
        case .monthly:
            return balance * rate / Decimal(12)
        }
    }

    // MARK: Init

    init(
        name: String,
        lenderName: String,
        currency: String,
        creditLimit: Decimal,
        annualInterestRate: Decimal,
        compounding: CreditLineCompounding = .daily,
        minimumPaymentType: MinimumPaymentType = .interestOnly,
        minimumPaymentValue: Decimal = 0,
        account: Account? = nil,
        notes: String? = nil
    ) {
        self.name = name
        self.lenderName = lenderName
        self.currency = currency
        self.creditLimit = creditLimit
        self.annualInterestRate = annualInterestRate
        self.compoundingRaw = compounding.rawValue
        self.minimumPaymentTypeRaw = minimumPaymentType.rawValue
        self.minimumPaymentValue = minimumPaymentValue
        self.lastInterestAccrualDate = Calendar.current.startOfDay(for: .now)
        self.isActive = true
        self.account = account
        self.notes = notes
        self.createdAt = .now
    }
}
