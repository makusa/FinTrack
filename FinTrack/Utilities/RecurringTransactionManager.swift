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
                debit.recurringRule   = rule
                credit.recurringRule  = rule
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
                tx.recurringRule = rule
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
            debit.recurringRule = rule; credit.recurringRule = rule
            context.insert(debit); context.insert(credit)
        } else {
            let tx = Transaction(
                amount: rule.amount, type: rule.type, date: .now,
                account: rule.account, category: rule.category,
                note: rule.note, payee: rule.payee,
                sourceRecurringId: rule.persistentModelID.hashValue
            )
            tx.savingsProject = rule.savingsProject
            tx.recurringRule = rule
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


// MARK: - Scoped edit / delete (toutes les transactions vs uniquement à venir)

/// Portée d'une modification ou suppression sur une règle récurrente.
enum RecurringEditScope {
    case allTransactions   // applique aussi à l'historique déjà généré
    case futureOnly        // n'affecte que la règle (occurrences futures)
}

extension RecurringTransactionManager {

    /// Vrai si la règle a déjà généré au moins une transaction (donc un historique
    /// existe et le choix « toutes / à venir » a du sens).
    static func hasGeneratedTransactions(_ rule: RecurringTransaction) -> Bool {
        !(rule.generatedTransactions ?? []).isEmpty
    }

    /// Réécrit les VALEURS actuelles de la règle sur toutes les transactions déjà
    /// générées. À appeler APRÈS avoir mis à jour les champs de la règle.
    /// Transferts : seul le montant est propagé — le sens et les comptes des deux
    /// jambes sont structurels et restent intacts. Les dates ne sont jamais touchées.
    static func propagateValuesToGeneratedTransactions(_ rule: RecurringTransaction,
                                                        context: ModelContext) {
        let txs = rule.generatedTransactions ?? []
        guard !txs.isEmpty else { return }

        for tx in txs {
            if rule.isTransfer {
                tx.amount = rule.amount
            } else {
                tx.amount   = rule.amount
                tx.type     = rule.type
                tx.account  = rule.account
                tx.category = rule.category
                tx.payee    = rule.payee
                tx.note     = rule.note
            }
        }

        recalculateAllAccounts(context: context)
        try? context.save()
    }

    /// Supprime une règle et, selon la portée, ses transactions générées.
    /// `.allTransactions` → la règle + toutes les transactions générées.
    /// `.futureOnly`      → la règle + uniquement les transactions à venir
    ///                      (date > maintenant) ; l'historique est conservé.
    static func deleteRule(_ rule: RecurringTransaction,
                           scope: RecurringEditScope,
                           context: ModelContext) {
        let now = Date()
        // Capturer les transactions AVANT de supprimer la règle.
        let txs = rule.generatedTransactions ?? []
        for tx in txs where scope == .allTransactions || tx.date > now {
            context.delete(tx)
        }
        context.delete(rule)
        try? context.save()           // purge les suppressions, relations cohérentes

        recalculateAllAccounts(context: context)
        try? context.save()
    }

    /// Recalcule le solde caché de tous les comptes. Le faible nombre de comptes
    /// rend l'opération triviale et garantit qu'aucun compte touché n'est oublié.
    private static func recalculateAllAccounts(context: ModelContext) {
        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        for a in accounts { a.recalculateBalance() }
    }
}


extension RecurringTransactionManager {

    /// True if the rule has at least one past-due (missed) occurrence relative to today.
    static func hasMissedOccurrences(_ rule: RecurringTransaction) -> Bool {
        rule.nextDueDate < Calendar.current.startOfDay(for: .now)
    }

    /// Advance `nextDueDate` to the next occurrence on or after today, skipping every
    /// past-due (missed) occurrence. Used when resuming a paused rule without catch-up.
    static func skipMissedOccurrences(_ rule: RecurringTransaction) {
        let today = Calendar.current.startOfDay(for: .now)
        var guardCount = 0
        while rule.nextDueDate < today && guardCount < 100_000 {
            rule.nextDueDate = rule.frequency.nextDate(after: rule.nextDueDate)
            guardCount += 1
        }
    }
}

extension RecurringTransactionManager {

    /// Skip the next scheduled occurrence: advance `nextDueDate` one period forward
    /// WITHOUT generating a transaction. Deactivates the rule if this passes its end date.
    static func skipNextOccurrence(_ rule: RecurringTransaction) {
        rule.nextDueDate = rule.frequency.nextDate(after: rule.nextDueDate)
        if let end = rule.endDate, rule.nextDueDate > end {
            rule.isActive = false
        }
    }
}
