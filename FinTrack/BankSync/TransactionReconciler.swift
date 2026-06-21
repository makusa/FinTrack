//
//  TransactionReconciler.swift
//  FinTrack
//
//  Provider-neutral reconciliation of incoming bank transactions.
//
//  Each provider engine (Flinks, Plaid, …) is only responsible for fetching and
//  decoding its own payload, then mapping it to [IncomingBankTransaction]. ALL
//  domain logic — dedup, Option-C matching against manual entries, status
//  stamping and balance recomputation — lives here, written once. No provider
//  data type is allowed past this boundary (anti-corruption layer).
//

import Foundation
import SwiftData

/// A bank transaction normalized away from any provider's DTO.
struct IncomingBankTransaction {
    let externalId: String        // provider's stable id (Flinks Id / Plaid transaction_id)
    let accountKey: String        // FinTrack Account.uuid of the resolved target account
    let isIncome: Bool
    let amount: Decimal           // always positive
    let date: Date
    let payee: String?            // provider-formatted display payee
    let note: String              // provider-formatted note
    let bankDescription: String?  // raw bank description, preserved on the row
    var category: Category? = nil // resolved during manual import review; nil for live sync
}

enum TransactionReconciler {

    struct Outcome {
        let added: Int        // new synced rows with no manual match
        let reconciled: Int   // manual rows auto-linked to a synced row (Option C)
        let flagged: Int      // synced rows flagged as possible duplicates
        let skipped: Int      // already-synced (dedup) or unresolvable account
    }

    /// Reconcile a batch of incoming bank transactions against the store:
    ///  - dedup against already-synced rows by externalId;
    ///  - Option-C matching against manual entries (auto-link / review queue);
    ///  - stamp synced/adopted rows .reconciled (ambiguous → needsReview);
    ///  - recompute balances of affected accounts; persist.
    /// The batch may span multiple accounts; matching is account-scoped.
    static func reconcile(_ incoming: [IncomingBankTransaction], context: ModelContext) -> Outcome {
        guard !incoming.isEmpty else {
            return Outcome(added: 0, reconciled: 0, flagged: 0, skipped: 0)
        }

        let existing = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
        var knownIds = Set(existing.compactMap { $0.externalId })

        // Manual rows a synced row could reconcile against (Option C).
        // externalId == nil = not yet bank-backed; .skipped = user opted out.
        let manualRows = existing.filter {
            $0.externalId == nil && $0.status != .skipped && $0.account != nil
        }
        var candidateMap: [String: Transaction] = [:]
        var allCandidates: [MatchCandidate] = []
        for (i, m) in manualRows.enumerated() {
            let key = "c\(i)"
            candidateMap[key] = m
            allCandidates.append(MatchCandidate(
                id: key,
                accountKey: m.account!.uuid,
                isIncome: m.type == .income,
                amount: m.amount,
                date: m.date
            ))
        }
        var consumed = Set<String>()

        let allAccounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        var accountByKey: [String: Account] = [:]
        for a in allAccounts { accountByKey[a.uuid] = a }
        var affected: Set<PersistentIdentifier> = []

        var added = 0, reconciled = 0, flagged = 0, skipped = 0

        for inc in incoming {
            guard !knownIds.contains(inc.externalId) else { skipped += 1; continue }
            guard let target = accountByKey[inc.accountKey] else { skipped += 1; continue }

            let liveCandidates = allCandidates.filter { !consumed.contains($0.id) }
            let decision = TransactionMatcher.decide(
                incomingAccountKey: inc.accountKey,
                incomingIsIncome: inc.isIncome,
                incomingAmount: inc.amount,
                incomingDate: inc.date,
                candidates: liveCandidates
            )

            switch decision {
            case .autoLink(let candId):
                // Adopt the manual row: stamp it bank-backed + reconciled, keep the
                // user's category/note/payee, store the raw bank description.
                if let manual = candidateMap[candId] {
                    manual.externalId = inc.externalId
                    manual.bankDescription = inc.bankDescription
                    manual.status = .reconciled
                    consumed.insert(candId)
                    knownIds.insert(inc.externalId)
                    if let a = manual.account { affected.insert(a.persistentModelID) }
                    reconciled += 1
                }

            case .review:
                // Ambiguous: insert the synced row but flag it for user review.
                let tx = makeRow(inc, target: target)
                tx.needsReview = true
                context.insert(tx)
                knownIds.insert(inc.externalId)
                affected.insert(target.persistentModelID)
                flagged += 1

            case .insertNew:
                let tx = makeRow(inc, target: target)
                context.insert(tx)
                knownIds.insert(inc.externalId)
                affected.insert(target.persistentModelID)
                added += 1
            }
        }

        allAccounts.filter { affected.contains($0.persistentModelID) }
                   .forEach { $0.recalculateBalance() }
        do {
            try context.save()
        } catch {
            AppLogger.persistence.error("TransactionReconciler save failed: \(error, privacy: .private)")
        }

        return Outcome(added: added, reconciled: reconciled, flagged: flagged, skipped: skipped)
    }

    /// Build a fresh synced transaction (no manual match) — reconciled, with the
    /// raw bank description preserved.
    private static func makeRow(_ inc: IncomingBankTransaction, target: Account) -> Transaction {
        let tx = Transaction(amount: inc.amount, type: inc.isIncome ? .income : .expense,
                             date: inc.date, account: target, category: inc.category,
                             note: inc.note, payee: inc.payee)
        tx.externalId = inc.externalId
        tx.bankDescription = inc.bankDescription
        tx.status = .reconciled
        return tx
    }
}
