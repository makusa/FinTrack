//
//  Account.swift
//  FinTrack
//
//  SwiftData model for a bank account, credit card, or cash wallet.
//  Multiple institutions and currencies are supported.
//

import Foundation
import SwiftData

enum AccountType: String, CaseIterable, Identifiable {
    case checking   // Compte courant
    case savings    // Compte épargne
    case credit     // Carte de crédit
    case cash       // Liquide
    case investment // Placement
    case other      // Autre

    var id: String { rawValue }

    var label: String {
        switch self {
        case .checking:   return LanguageManager.shared["account.type.checking"]
        case .savings:    return LanguageManager.shared["account.type.savings"]
        case .credit:     return LanguageManager.shared["account.type.credit"]
        case .cash:       return LanguageManager.shared["account.type.cash"]
        case .investment: return LanguageManager.shared["account.type.investment"]
        case .other:      return LanguageManager.shared["account.type.other"]
        }
    }

    var defaultIconSystemName: String {
        switch self {
        case .checking:   return "building.columns.fill"
        case .savings:    return "banknote.fill"
        case .credit:     return "creditcard.fill"
        case .cash:       return "dollarsign.circle.fill"
        case .investment: return "chart.line.uptrend.xyaxis"
        case .other:      return "wallet.pass.fill"
        }
    }
}

@Model
final class Account {
    var name: String = ""
    var institution: String = ""
    var typeRaw: String = AccountType.checking.rawValue
    var currency: String = Currencies.default  // ISO 4217 code
    var initialBalance: Decimal = Decimal(0)
    var colorHex: String = "#3478F6"
    var iconSystemName: String = AccountType.checking.defaultIconSystemName
    var isArchived: Bool = false
    var notes: String?
    var bankDomain: String? = nil   // Clearbit/favicon domain for logo; nil = SF Symbol
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \Transaction.account)
    var transactions: [Transaction]? = []

    // CloudKit inverse back-references. Declared here without @Relationship
    // so SwiftData infers them from the child-side @Relationship(inverse:).
    var loans:               [Loan]?               = []
    var savingsProjects:     [SavingsProject]?      = []
    var recurringRules:      [RecurringTransaction]? = []
    var incomingTransfers:   [RecurringTransaction]? = []
    var loanPrepayments:     [LoanPrepayment]?      = []
    var creditLineEntries:   [CreditLineEntry]?     = []
    var creditLines:         [CreditLine]?          = []


    var type: AccountType {
        get { AccountType(rawValue: typeRaw) ?? .other }
        set { typeRaw = newValue.rawValue }
    }

    /// Denormalised balance — cached for O(1) reads (C1 perf fix).
    /// Updated by recalculateBalance() on every transaction write.
    var cachedBalance: Decimal = 0

    /// O(1) read — returns the cached value.
    var balance: Decimal { cachedBalance }

    /// Full recomputation from scratch. Call after any write that touches
    /// this account's transactions or initialBalance.
    func recalculateBalance() {
        cachedBalance = (transactions ?? []).reduce(initialBalance) { $0 + $1.signedAmount }
    }

    init(
        name: String,
        institution: String,
        type: AccountType,
        currency: String,
        initialBalance: Decimal = 0,
        colorHex: String = "#3478F6",
        iconSystemName: String? = nil,
        notes: String? = nil
    ) {
        self.name = name
        self.institution = institution
        self.typeRaw = type.rawValue
        self.currency = currency
        self.initialBalance = initialBalance
        self.colorHex = colorHex
        self.iconSystemName = iconSystemName ?? type.defaultIconSystemName
        self.isArchived = false
        self.notes = notes
        self.createdAt = Date.now
    }
}
