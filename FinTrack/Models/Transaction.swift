//
//  Transaction.swift
//  FinTrack
//
//  A single income or expense entry on an account.
//  Amount is ALWAYS stored as a positive Decimal; sign is derived from `type`.
//

import Foundation
import SwiftData

enum TransactionType: String, CaseIterable, Identifiable {
    case income   // Revenu
    case expense  // Dépense

    var id: String { rawValue }

    var labelFR: String {
        switch self {
        case .income:  return "Revenu"
        case .expense: return "Dépense"
        }
    }

    /// Sign multiplier applied to the positive amount when computing balances.
    var sign: Decimal {
        switch self {
        case .income:  return 1
        case .expense: return -1
        }
    }
}

@Model
final class Transaction {
    var amount: Decimal           // always positive
    var typeRaw: String
    var date: Date
    var note: String
    var payee: String?
    var createdAt: Date
    var ownerId: UUID             // foyer-readiness: solo mode uses a constant

    var account: Account?
    var category: Category?

    var type: TransactionType {
        get { TransactionType(rawValue: typeRaw) ?? .expense }
        set { typeRaw = newValue.rawValue }
    }

    /// Positive for income, negative for expense.
    var signedAmount: Decimal {
        amount * type.sign
    }

    init(
        amount: Decimal,
        type: TransactionType,
        date: Date = .now,
        account: Account? = nil,
        category: Category? = nil,
        note: String = "",
        payee: String? = nil,
        ownerId: UUID = AppConstants.soloOwnerId
    ) {
        self.amount = amount
        self.typeRaw = type.rawValue
        self.date = date
        self.note = note
        self.payee = payee
        self.createdAt = .now
        self.ownerId = ownerId
        self.account = account
        self.category = category
    }
}

/// App-wide constants. The solo owner ID is constant across the app so that
/// when foyer mode launches, existing rows are trivially attributable to the
/// device owner and can be migrated without data juggling.
enum AppConstants {
    static let soloOwnerId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
}
