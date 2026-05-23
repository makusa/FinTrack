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
    var initialBalance: Decimal = 0
    var colorHex: String = "#3478F6"
    var iconSystemName: String = AccountType.checking.defaultIconSystemName
    var isArchived: Bool = false
    var notes: String?
    var createdAt: Date = .now

    @Relationship(deleteRule: .cascade, inverse: \Transaction.account)
    var transactions: [Transaction] = []

    var type: AccountType {
        get { AccountType(rawValue: typeRaw) ?? .other }
        set { typeRaw = newValue.rawValue }
    }

    /// Computed balance = initial balance + sum of signed transactions.
    /// We never store this; the source of truth is always the transaction history.
    var balance: Decimal {
        transactions.reduce(initialBalance) { partial, tx in
            partial + tx.signedAmount
        }
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
        self.createdAt = .now
    }
}
