//
//  SavingsTransferService.swift
//  FinTrack
//
//  Creates / updates / removes the RecurringTransaction that materialises a
//  savings project's automatic contributions, keeping a reliable link between
//  the project and both the rule and the transactions it generates.
//

import Foundation
import SwiftData

enum SavingsTransferService {

    /// Creates or updates the recurring rule for a project's auto-transfer.
    /// Call on save when `autoTransferEnabled` is true.
    /// - No tracking account  → recurring expense, payee = project name (the beneficiary).
    /// - Tracking account set → transfer (two legs): debit source → credit savings account.
    static func syncRule(for project: SavingsProject, source: Account, context: ModelContext) {
        let amount   = project.monthlyContribution
        let freq     = project.transferFrequency
        let ruleName = project.name.trimmingCharacters(in: .whitespaces).isEmpty
            ? LanguageManager.shared["savings.title"]
            : project.name
        let note     = LanguageManager.shared["savings.contribution"] + " — " + ruleName

        let existing = (project.recurringTransactions ?? []).first

        // Did the schedule (frequency or day) change vs the existing rule?
        let scheduleChanged: Bool = {
            guard let r = existing else { return true }
            let comp: Calendar.Component = SavingsTransferSchedule.isWeekdayBased(freq) ? .weekday : .day
            let currentDay = Calendar.current.component(comp, from: r.startDate)
            return r.frequency != freq || currentDay != project.transferDay
        }()

        let rule: RecurringTransaction
        if let r = existing {
            rule = r
        } else {
            rule = RecurringTransaction(
                title: ruleName, amount: amount, type: .expense,
                frequency: freq, startDate: Date(), account: source)
            context.insert(rule)
        }

        rule.title          = ruleName
        rule.amount         = amount
        rule.frequency      = freq
        rule.account        = source
        rule.note           = note
        rule.savingsProject = project
        rule.isActive       = true

        if project.trackViaAccount, let savings = project.account {
            // Transfer: debit source → credit savings account
            rule.isTransfer         = true
            rule.destinationAccount = savings
            rule.payee              = nil
        } else {
            // Plain recurring expense, beneficiary = goal name
            rule.isTransfer         = false
            rule.destinationAccount = nil
            rule.payee              = ruleName
        }

        if existing == nil || scheduleChanged {
            let start = SavingsTransferSchedule.firstDate(
                frequency: freq, day: project.transferDay, onOrAfter: Date())
            rule.startDate   = start
            rule.nextDueDate = start
        }
    }

    /// Disables auto-transfer: deletes the linked rule(s). When `removePast` is
    /// true, also deletes the already-generated transactions (both transfer legs)
    /// and recalculates affected account balances.
    static func disableAutoTransfer(for project: SavingsProject, removePast: Bool, context: ModelContext) {
        for rule in (project.recurringTransactions ?? []) {
            context.delete(rule)
        }
        if removePast {
            let now = Date()
            let toDelete = (project.generatedTransactions ?? []).filter { $0.date <= now }
            let touched  = Set(toDelete.compactMap { $0.account })
            for tx in toDelete { context.delete(tx) }
            for acc in touched { acc.recalculateBalance() }
            project.account?.recalculateBalance()
        }
        project.autoTransferEnabled = false
    }

    /// Removes a project's rule(s) and (optionally) generated transactions when the
    /// project itself is being deleted (avoids orphaned active rules).
    static func cleanupOnDelete(_ project: SavingsProject, removeGenerated: Bool, context: ModelContext) {
        disableAutoTransfer(for: project, removePast: removeGenerated, context: context)
    }

    /// True when the project already has materialised (past) transactions — drives
    /// the "remove past or only future?" confirmation.
    static func hasPastTransactions(_ project: SavingsProject) -> Bool {
        let now = Date()
        return (project.generatedTransactions ?? []).contains { $0.date <= now }
    }
}
