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

    var labelFR: String {
        switch self {
        case .checking:   return "Compte courant"
        case .savings:    return "Épargne"
        case .credit:     return "Carte de crédit"
        case .cash:       return "Liquide"
        case .investment: return "Placement"
        case .other:      return "Autre"
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
    var name: String
    var institution: String
    var typeRaw: String
    var currency: String        // ISO 4217 code
    var initialBalance: Decimal
    var colorHex: String
    var iconSystemName: String
    var isArchived: Bool
    var notes: String?
    var createdAt: Date

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
