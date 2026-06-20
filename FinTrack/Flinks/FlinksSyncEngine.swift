//
//  FlinksSyncEngine.swift
//  FinTrack
//
//  Converts Flinks transactions into FinTrack Transaction records.
//  Dedup key: Flinks Transaction.Id, stored in Transaction.externalId.
//  Flinks has no incremental cursor — we fetch recent activity and
//  deduplicate by external ID.
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
        let loginId: String
        let added:   Int
        let skipped: Int
        let error:   Error?
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

            // Existing external IDs — one fetch, O(1) lookups (N1 lesson).
            let existing = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
            var knownIds = Set(existing.compactMap { $0.externalId })

            let allAccounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
            var affectedAccounts: Set<PersistentIdentifier> = []

            var added = 0, skipped = 0
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            df.timeZone = TimeZone(identifier: "America/Toronto")

            for flinksAccount in detail.accounts {
                // Resolve mapping FlinksAccount → FinTrack Account
                guard let meta = login.accounts.first(where: { $0.id == flinksAccount.id }),
                      let mappedId = meta.fintrackAccountId,
                      let target = allAccounts.first(where: { "\($0.persistentModelID.hashValue)" == mappedId
                                                              || $0.name == mappedId })
                else { continue }   // unmapped accounts are skipped silently

                for ftx in flinksAccount.transactions ?? [] {
                    guard !knownIds.contains(ftx.id) else { skipped += 1; continue }
                    guard let date = df.date(from: ftx.date) else { skipped += 1; continue }

                    let isCredit = (ftx.credit ?? 0) > 0
                    let amount = Decimal(isCredit ? (ftx.credit ?? 0) : (ftx.debit ?? 0))
                    guard amount > 0 else { skipped += 1; continue }

                    let tx = Transaction(
                        amount: amount,
                        type: isCredit ? .income : .expense,
                        date: date,
                        account: target,
                        category: nil,
                        note: "",
                        payee: ftx.description
                    )
                    tx.externalId = ftx.id
                    tx.bankDescription = ftx.description
                    tx.status = .reconciled
                    context.insert(tx)
                    knownIds.insert(ftx.id)
                    affectedAccounts.insert(target.persistentModelID)
                    added += 1
                }
            }

            // C1 — denormalised balances must be recalculated after writes.
            allAccounts.filter { affectedAccounts.contains($0.persistentModelID) }
                       .forEach { $0.recalculateBalance() }
            try? context.save()

            // Update lastSyncDate
            if var updated = FlinksManager.shared.connectedLogins.first(where: { $0.id == login.id }) {
                updated.lastSyncDate = .now
                FlinksManager.shared.addLogin(updated)
            }

            syncLog.info("Flinks sync: \(added) added, \(skipped) skipped")
            return SyncResult(loginId: login.id, added: added, skipped: skipped, error: nil)
        } catch {
            syncLog.error("Flinks sync failed: \(error, privacy: .private)")
            return SyncResult(loginId: login.id, added: 0, skipped: 0, error: error)
        }
    }
}
