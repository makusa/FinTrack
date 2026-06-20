//
//  FlinksSyncEngine.swift
//  FinTrack
//
//  Flinks adapter: fetches Flinks activity, maps it to the provider-neutral
//  IncomingBankTransaction, and hands it to TransactionReconciler. All dedup,
//  Option-C matching, status stamping and balance recomputation live in the
//  shared reconciler — no Flinks type leaks past the mapping below.
//

import Foundation
import SwiftData
import os

private let syncLog = Logger(subsystem: "ca.regis.fintrack", category: "flinks-sync")

@MainActor
final class FlinksSyncEngine {

    static let shared = FlinksSyncEngine()
    private init() {}

    struct SyncResult {
        let loginId:    String
        let added:      Int   // new synced rows with no manual match
        let reconciled: Int   // manual rows auto-linked to a synced row (Option C)
        let flagged:    Int   // synced rows flagged as possible duplicates (needs review)
        let skipped:    Int
        let error:      Error?
    }

    // MARK: - Sync all connected logins

    func syncAll(context: ModelContext) async -> [SyncResult] {
        var results: [SyncResult] = []
        for login in FlinksManager.shared.connectedLogins {
            results.append(await sync(login: login, context: context))
        }
        return results
    }

    func sync(login: FlinksConnectedLogin, context: ModelContext) async -> SyncResult {
        do {
            let requestId = try await FlinksManager.shared.authorize(loginId: login.id)
            let detail = try await FlinksManager.shared.getAccountsDetail(requestId: requestId)

            let allAccounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []

            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            df.timeZone = TimeZone(identifier: "America/Toronto")

            // ── Anti-corruption layer: Flinks DTO → neutral incoming rows ──
            var incoming: [IncomingBankTransaction] = []
            var preSkipped = 0   // dropped before reconciliation (bad date / non-positive amount)

            for flinksAccount in detail.accounts {
                // Resolve mapping FlinksAccount → FinTrack Account (provider-specific).
                guard let meta = login.accounts.first(where: { $0.id == flinksAccount.id }),
                      let mappedId = meta.fintrackAccountId,
                      let target = allAccounts.first(where: { "\($0.persistentModelID.hashValue)" == mappedId
                                                              || $0.name == mappedId })
                else { continue }   // unmapped accounts are skipped silently

                for ftx in flinksAccount.transactions ?? [] {
                    guard let date = df.date(from: ftx.date) else { preSkipped += 1; continue }
                    let isCredit = (ftx.credit ?? 0) > 0
                    let amount = Decimal(isCredit ? (ftx.credit ?? 0) : (ftx.debit ?? 0))
                    guard amount > 0 else { preSkipped += 1; continue }

                    incoming.append(IncomingBankTransaction(
                        externalId: ftx.id,
                        accountKey: target.uuid,
                        isIncome: isCredit,
                        amount: amount,
                        date: date,
                        payee: ftx.description,
                        note: "",
                        bankDescription: ftx.description
                    ))
                }
            }

            // ── Provider-neutral reconciliation ──
            let outcome = TransactionReconciler.reconcile(incoming, context: context)

            // Update lastSyncDate
            if var updated = FlinksManager.shared.connectedLogins.first(where: { $0.id == login.id }) {
                updated.lastSyncDate = .now
                FlinksManager.shared.addLogin(updated)
            }

            let skipped = outcome.skipped + preSkipped
            syncLog.info("Flinks sync: \(outcome.added) added, \(outcome.reconciled) reconciled, \(outcome.flagged) flagged, \(skipped) skipped")
            return SyncResult(loginId: login.id, added: outcome.added, reconciled: outcome.reconciled,
                              flagged: outcome.flagged, skipped: skipped, error: nil)
        } catch {
            syncLog.error("Flinks sync failed: \(error, privacy: .private)")
            return SyncResult(loginId: login.id, added: 0, reconciled: 0,
                              flagged: 0, skipped: 0, error: error)
        }
    }
}
