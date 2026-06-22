//
//  RecurringTransactionManager.swift
//  FinTrack
//
//  Generates Transaction entries from active RecurringTransaction rules.
//  Called once at app launch. Safe to call multiple times — it is idempotent
//  because nextDueDate advances past the current date after each run.
//

import Foundation
import SwiftData

enum RecurringTransactionManager {

    // MARK: - Public API

    /// Apply all pending recurring rules up to today's date.
    /// Inserts the generated Transaction objects and saves the context.
    static func applyPending(context: ModelContext) {
        let now = Date()
        let descriptor = FetchDescriptor<RecurringTransaction>(
            predicate: #Predicate { $0.isActive }
        )
        let rules = (try? context.fetch(descriptor)) ?? []

        var didChange = false
        for rule in rules {
            if generateTransactions(for: rule, upTo: now, context: context) {
                didChange = true
            }
        }

        if didChange {
            // Recalculate balance for all accounts touched by this run
            for rule in rules {
                rule.account?.recalculateBalance()
                rule.destinationAccount?.recalculateBalance()
            }
            try? context.save()
        }
    }

    // MARK: - Internal

    /// Generates one or more Transaction entries for `rule`, up to `date`.
    /// Returns true if at least one transaction was inserted.
    @discardableResult
    private static func generateTransactions(
        for rule: RecurringTransaction,
        upTo date: Date,
        context: ModelContext
    ) -> Bool {
        var inserted = false
        var dueDate = rule.nextDueDate

        while dueDate <= date {
            // Respect end date: deactivate the rule and stop.
            if let end = rule.endDate, dueDate > end {
                rule.isActive = false
                break
            }

            if rule.isTransfer, let destination = rule.destinationAccount {
                // Transfer: generate two linked transactions
                let pairId = UUID()
                let debit = Transaction(
                    amount: rule.amount,
                    type: .expense,
                    date: dueDate,
                    account: rule.account,
                    category: nil,
                    note: rule.note.isEmpty ? "\(LanguageManager.shared["transfer.to.label"]) \(destination.name)" : rule.note,
                    payee: destination.name,
                    sourceRecurringId: rule.persistentModelID.hashValue
                )
                debit.transferPairId = pairId
                let credit = Transaction(
                    amount: rule.amount,
                    type: .income,
                    date: dueDate,
                    account: destination,
                    category: nil,
                    note: rule.note.isEmpty ? "\(LanguageManager.shared["transfer.from.label"]) \(rule.account?.name ?? "")" : rule.note,
                    payee: rule.account?.name,
                    sourceRecurringId: rule.persistentModelID.hashValue
                )
                credit.transferPairId = pairId
                debit.savingsProject  = rule.savingsProject
                credit.savingsProject = rule.savingsProject
                context.insert(debit)
                context.insert(credit)
            } else {
                let tx = Transaction(
                    amount: rule.amount,
                    type: rule.type,
                    date: dueDate,
                    account: rule.account,
                    category: rule.category,
                    note: rule.note,
                    payee: rule.payee,
                    sourceRecurringId: rule.persistentModelID.hashValue  // link for traceability
                )
                tx.savingsProject = rule.savingsProject
                context.insert(tx)
            }
            inserted = true

            dueDate = rule.frequency.nextDate(after: dueDate)
        }

        // Advance nextDueDate so the next call knows where to start.
        rule.nextDueDate = dueDate
        return inserted
    }

    // MARK: - Manual trigger

    /// Generate and save a single occurrence NOW (manual "post early" action).
    static func postNow(_ rule: RecurringTransaction, context: ModelContext) {
        if rule.isTransfer, let destination = rule.destinationAccount {
            let pairId = UUID()
            let debit = Transaction(amount: rule.amount, type: .expense, date: .now,
                account: rule.account, note: rule.note.isEmpty ? "\(LanguageManager.shared["transfer.to.label"]) \(destination.name)" : rule.note,
                payee: destination.name, sourceRecurringId: rule.persistentModelID.hashValue)
            debit.transferPairId = pairId
            let credit = Transaction(amount: rule.amount, type: .income, date: .now,
                account: destination, note: rule.note.isEmpty ? "\(LanguageManager.shared["transfer.from.label"]) \(rule.account?.name ?? "")" : rule.note,
                payee: rule.account?.name, sourceRecurringId: rule.persistentModelID.hashValue)
            credit.transferPairId = pairId
            debit.savingsProject = rule.savingsProject; credit.savingsProject = rule.savingsProject
            context.insert(debit); context.insert(credit)
        } else {
            let tx = Transaction(
                amount: rule.amount, type: rule.type, date: .now,
                account: rule.account, category: rule.category,
                note: rule.note, payee: rule.payee,
                sourceRecurringId: rule.persistentModelID.hashValue
            )
            tx.savingsProject = rule.savingsProject
            context.insert(tx)
        }
        // Advance the due date by one period.
        rule.nextDueDate = rule.frequency.nextDate(after: rule.nextDueDate)
        // Recalculate balance for accounts touched by this manual post
        rule.account?.recalculateBalance()
        if rule.isTransfer, let destination = rule.destinationAccount {
            destination.recalculateBalance()
        }
        try? context.save()
    }
}
