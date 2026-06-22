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

    var label: String {
        switch self {
        case .income:  return LanguageManager.shared["tx.type.income"]
        case .expense: return LanguageManager.shared["tx.type.expense"]
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

/// Lifecycle + reconciliation status of a transaction, ordered by confidence.
/// One badge per transaction. The possible-duplicate flag is kept separate
/// (see `needsReview`) so this stays a clean monotonic progression.
enum TransactionStatus: String, CaseIterable, Identifiable {
    case scheduled    // Planifié — future, pas encore survenue
    case pending      // En attente — autorisé mais non réglé (réservé : Flinks ne l'expose pas encore)
    case cleared      // Réalisé — survenue et enregistrée, non confirmée par la banque
    case reconciled   // Réconcilié — adossée aux données bancaires (synchro ou appariement)
    case skipped      // Ignoré — occurrence récurrente sautée

    var id: String { rawValue }

    var label: String {
        switch self {
        case .scheduled:  return LanguageManager.shared["tx.status.scheduled"]
        case .pending:    return LanguageManager.shared["tx.status.pending"]
        case .cleared:    return LanguageManager.shared["tx.status.cleared"]
        case .reconciled: return LanguageManager.shared["tx.status.reconciled"]
        case .skipped:    return LanguageManager.shared["tx.status.skipped"]
        }
    }

    /// SF Symbol for the status badge (colors are applied in the view layer).
    var iconSystemName: String {
        switch self {
        case .scheduled:  return "calendar"
        case .pending:    return "clock"
        case .cleared:    return "checkmark.circle"
        case .reconciled: return "checkmark.seal.fill"
        case .skipped:    return "minus.circle"
        }
    }

    /// Whether a transaction in this status contributes to the real (cleared)
    /// balance. Future (scheduled) and skipped entries are excluded — they feed
    /// projections only, never the current balance.
    var countsTowardBalance: Bool {
        switch self {
        case .cleared, .reconciled, .pending: return true
        case .scheduled, .skipped:            return false
        }
    }

    /// Default status for a freshly entered *manual* transaction with this date:
    /// future-dated → scheduled, otherwise → cleared.
    static func defaultForManual(date: Date, now: Date = .now) -> TransactionStatus {
        date > now ? .scheduled : .cleared
    }
}

@Model
final class Transaction {
    var amount: Decimal = 0          // always positive
    var typeRaw: String = TransactionType.expense.rawValue
    var date: Date = Date.now
    var note: String = ""
    var payee: String?
    var createdAt: Date = Date.now
    // MARK: Notification settings
    var notificationEnabled: Bool = false
    var notificationDaysBefore: Int = 1


    var ownerId: UUID = AppConstants.soloOwnerId  // foyer-readiness: solo mode uses a constant
    /// Hash of the PersistentModelID of the RecurringTransaction that generated
    /// this entry. nil = saisie manuelle. Stored as plain Int (not a relationship)
    /// to avoid circular SwiftData constraints.
    var sourceRecurringId: Int?
    var transferPairId: UUID? = nil   // links the two legs of a transfer
    var externalId: String? = nil  // Bank-sync deduplication ID (Flinks Transaction.Id)

    /// Lifecycle + reconciliation status (see TransactionStatus). Defaults to
    /// .cleared; the launch sweep keeps it in sync (bank-backed → reconciled,
    /// manual scheduled/cleared reclassified by date).
    var statusRaw: String = TransactionStatus.cleared.rawValue
    /// Raw bank/Flinks description, preserved when a synced row adopts a manual one.
    var bankDescription: String? = nil
    /// Option C: flagged as a possible duplicate of a manual entry, pending user review.
    var needsReview: Bool = false

    var account: Account?
    var category: Category?

    /// Savings project whose auto-transfer generated this entry (reliable cleanup).
    @Relationship(deleteRule: .nullify, inverse: \SavingsProject.generatedTransactions)
    var savingsProject: SavingsProject? = nil

    var type: TransactionType {
        get { TransactionType(rawValue: typeRaw) ?? .expense }
        set { typeRaw = newValue.rawValue }
    }

    var status: TransactionStatus {
        get { TransactionStatus(rawValue: statusRaw) ?? .cleared }
        set { statusRaw = newValue.rawValue }
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
        ownerId: UUID = AppConstants.soloOwnerId,
        sourceRecurringId: Int? = nil,
        status: TransactionStatus? = nil
    ) {
        self.amount = amount
        self.typeRaw = type.rawValue
        self.date = date
        self.note = note
        self.payee = payee
        self.createdAt = .now
        self.ownerId = ownerId
        self.sourceRecurringId = sourceRecurringId
        self.statusRaw = (status ?? TransactionStatus.defaultForManual(date: date)).rawValue
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
