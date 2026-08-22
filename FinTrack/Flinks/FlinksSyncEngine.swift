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

    /// A per-account balance mismatch found after sync: the account's computed
    /// balance doesn't match the real balance Flinks reports. Non-blocking — the
    /// UI surfaces it and lets the user adjust (via OFXImportService).
    struct BalanceDiscrepancy: Identifiable {
        var id: String { accountUuid }
        let accountUuid: String
        let accountName: String
        let check: OFXImportService.BalanceCheck
    }

    struct SyncResult {
        let loginId:    String
        let added:      Int   // new synced rows with no manual match
        let reconciled: Int   // manual rows auto-linked to a synced row (Option C)
        let flagged:    Int   // synced rows flagged as possible duplicates (needs review)
        let skipped:    Int
        let discrepancies: [BalanceDiscrepancy]   // per-account balance mismatches (Flinks vs app)
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

            var mappedForBalance: [(account: Account, flinksBalance: Double, currency: String?)] = []

            for flinksAccount in detail.accounts {
                // Resolve mapping FlinksAccount → FinTrack Account (provider-specific).
                guard let meta = login.accounts.first(where: { $0.id == flinksAccount.id }),
                      let mappedId = meta.fintrackAccountId,
                      let target = allAccounts.first(where: { "\($0.persistentModelID.hashValue)" == mappedId
                                                              || $0.name == mappedId })
                else { continue }   // unmapped accounts are skipped silently

                // Real balance reported by Flinks — used for the post-sync check.
                if let bal = flinksAccount.balance?.current {
                    mappedForBalance.append((target, bal, flinksAccount.currency))
                }

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

            // ── P1: post-sync balance check (real Flinks balance vs computed) ──
            var discrepancies: [BalanceDiscrepancy] = []
            for m in mappedForBalance {
                // Skip when Flinks reports a currency that differs from the account.
                if let cur = m.currency, cur != m.account.currency { continue }
                // Double → Decimal at 2 decimals, avoiding binary imprecision.
                let declared = Decimal(string: String(format: "%.2f", m.flinksBalance)) ?? Decimal(m.flinksBalance)
                if let check = OFXImportService.balanceCheck(declaredBalance: declared,
                                                             declaredDate: .now, account: m.account) {
                    discrepancies.append(BalanceDiscrepancy(accountUuid: m.account.uuid,
                                                            accountName: m.account.name,
                                                            check: check))
                }
            }

            // Update lastSyncDate
            if var updated = FlinksManager.shared.connectedLogins.first(where: { $0.id == login.id }) {
                updated.lastSyncDate = .now
                FlinksManager.shared.addLogin(updated)
            }

            let skipped = outcome.skipped + preSkipped
            syncLog.info("Flinks sync: \(outcome.added) added, \(outcome.reconciled) reconciled, \(outcome.flagged) flagged, \(skipped) skipped, \(discrepancies.count) balance gaps")
            return SyncResult(loginId: login.id, added: outcome.added, reconciled: outcome.reconciled,
                              flagged: outcome.flagged, skipped: skipped, discrepancies: discrepancies, error: nil)
        } catch {
            syncLog.error("Flinks sync failed: \(error, privacy: .private)")
            return SyncResult(loginId: login.id, added: 0, reconciled: 0,
                              flagged: 0, skipped: 0, discrepancies: [], error: error)
        }
    }
}
