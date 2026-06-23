//
//  TransactionStatusManager.swift
//  FinTrack
//
//  Idempotent maintenance of transaction lifecycle statuses. Safe to run on
//  every launch and after each bank sync.
//

import Foundation
import SwiftData

enum TransactionStatusManager {

    /// Maintenance sweep:
    ///  - bank-backed rows (externalId set) are forced to `.reconciled`;
    ///  - the manual scheduled/cleared lifecycle is reclassified by date
    ///    (future → `.scheduled`, otherwise → `.cleared`);
    ///  - `.skipped` and `.pending` are intentional overrides, left untouched.
    ///
    /// Recomputes balances of affected accounts when statuses change (the
    /// scheduled↔cleared transition changes what counts toward the balance).
    /// Idempotent: a second call with no date change is a no-op.
    static func sweep(context: ModelContext, now: Date = .now) {
        let all = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
        var affected: Set<PersistentIdentifier> = []
        var changed = false

        for tx in all {
            if tx.externalId != nil {
                if tx.status != .reconciled {
                    tx.status = .reconciled
                    changed = true
                    if let a = tx.account { affected.insert(a.persistentModelID) }
                }
            } else if tx.status == .scheduled || tx.status == .cleared {
                let target: TransactionStatus = tx.date > now ? .scheduled : .cleared
                if tx.status != target {
                    tx.status = target
                    changed = true
                    if let a = tx.account { affected.insert(a.persistentModelID) }
                }
            }
        }

        guard changed else { return }

        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        for account in accounts where affected.contains(account.persistentModelID) {
            account.recalculateBalance()
        }
        do {
            try context.save()
        } catch {
            AppLogger.persistence.error("TransactionStatusManager sweep save failed: \(error, privacy: .private)")
        }
    }
}

extension TransactionStatusManager {

    /// Toggle the "skipped" override on a transaction (excluded from the balance).
    /// Unskipping restores the natural status: reconciled if bank-backed, else
    /// scheduled/cleared by date.
    static func toggleSkip(_ tx: Transaction, context: ModelContext) {
        if tx.status == .skipped {
            tx.status = tx.externalId != nil
                ? .reconciled
                : TransactionStatus.defaultForManual(date: tx.date)
        } else {
            tx.status = .skipped
        }
        tx.account?.recalculateBalance()
        do { try context.save() } catch {
            AppLogger.persistence.error("toggleSkip save failed: \(error, privacy: .private)")
        }
    }

    /// Toggle manual reconciliation. Reconciled and cleared both count toward the
    /// balance, so no recalculation is required.
    static func toggleReconciled(_ tx: Transaction, context: ModelContext) {
        tx.status = (tx.status == .reconciled)
            ? TransactionStatus.defaultForManual(date: tx.date)
            : .reconciled
        do { try context.save() } catch {
            AppLogger.persistence.error("toggleReconciled save failed: \(error, privacy: .private)")
        }
    }
}
