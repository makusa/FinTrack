//
//  LoanPrepaymentManager.swift
//  FinTrack
//
//  Generates Transaction entries from LoanPrepayment records that have an
//  associated account. Called at app launch alongside RecurringTransactionManager.
//
//  Model:
//    - One-time prepayment: generates one Transaction on startDate, then sets
//      nextPostDate = .distantFuture so it is never re-generated.
//    - Recurring prepayment: generates one Transaction per occurrence from
//      (nextPostDate ?? startDate) up to today, then advances nextPostDate.
//
//  The loan calculator already accounts for prepayments independently via
//  prepaymentInstances(). This manager only handles the cash-flow side:
//  the debit from the source account.
//

import Foundation
import SwiftData

enum LoanPrepaymentManager {

    // MARK: - Public API

    /// Apply all pending prepayment-linked transactions up to today.
    /// Safe to call multiple times — idempotent via nextPostDate tracking.
    static func applyPending(context: ModelContext) {
        let now = Date()
        let descriptor = FetchDescriptor<LoanPrepayment>()
        let all = (try? context.fetch(descriptor)) ?? []

        var didChange = false
        for prep in all {
            guard prep.account != nil else { continue }
            if generateTransactions(for: prep, upTo: now, context: context) {
                didChange = true
            }
        }

        if didChange { try? context.save() }
    }

    // MARK: - Internal

    @discardableResult
    private static func generateTransactions(
        for prep: LoanPrepayment,
        upTo date: Date,
        context: ModelContext
    ) -> Bool {
        guard let account = prep.account else { return false }

        let lenderName = prep.loan?.lenderName ?? ""
        let baseNote   = prep.note ?? ""
        let txNote     = baseNote.isEmpty
            ? (lenderName.isEmpty ? LanguageManager.shared["prepayment.title"] : "\(LanguageManager.shared["prepayment.title"]) — \(lenderName)")
            : baseNote

        if prep.isRecurring, let freq = prep.frequency {
            // ── Recurring ──────────────────────────────────────────────────
            let startFrom = prep.nextPostDate ?? prep.startDate
            guard startFrom <= date else { return false }

            let hardStop: Date = {
                if let ed = prep.endDate { return ed }
                return Calendar.current.date(byAdding: .year, value: 50, to: prep.startDate) ?? date
            }()

            var cur = startFrom
            var inserted = false

            while cur <= min(date, hardStop) {
                let tx = Transaction(
                    amount:  prep.amount,
                    type:    .expense,
                    date:    cur,
                    account: account,
                    category: nil,
                    note:    txNote,
                    payee:   lenderName.isEmpty ? nil : lenderName
                )
                context.insert(tx)
                cur = freq.nextDate(after: cur)
                inserted = true
            }

            prep.nextPostDate = cur   // advance marker
            return inserted

        } else {
            // ── One-time ───────────────────────────────────────────────────
            // distantFuture sentinel means already posted
            if let nxt = prep.nextPostDate, nxt == .distantFuture { return false }
            guard prep.startDate <= date else { return false }

            let tx = Transaction(
                amount:  prep.amount,
                type:    .expense,
                date:    prep.startDate,
                account: account,
                category: nil,
                note:    txNote,
                payee:   lenderName.isEmpty ? nil : lenderName
            )
            context.insert(tx)
            prep.nextPostDate = .distantFuture   // mark as posted
            return true
        }
    }
}
