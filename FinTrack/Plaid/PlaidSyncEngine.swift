//
//  PlaidSyncEngine.swift
//  FinTrack
//
//  Converts Plaid transactions into FinTrack Transaction records.
//  Handles deduplication, currency mapping, and category matching.
//

import Foundation
import SwiftData

@MainActor
final class PlaidSyncEngine {

    static let shared = PlaidSyncEngine()
    private init() {}

    // MARK: - Sync all connected items

    /// A per-account balance mismatch found after a (recent) sync: the computed
    /// balance drifted from the real balance Plaid reports. Non-blocking — the UI
    /// surfaces it and lets the user adjust.
    struct BalanceDiscrepancy: Identifiable {
        var id: String { accountUuid }
        let accountUuid: String
        let accountName: String
        let check: OFXImportService.BalanceCheck
    }

    struct SyncResult {
        let itemId:     String
        let added:      Int
        let reconciled: Int   // manual rows auto-linked to a synced row (Option C)
        let flagged:    Int   // synced rows flagged as possible duplicates (needs review)
        let modified:   Int
        let removed:    Int
        let details:    [TransactionReconciler.ReconcileDetail]
        let discrepancies: [BalanceDiscrepancy]
        let error:      Error?
    }

    func syncAll(context: ModelContext) async -> [SyncResult] {
        let items = PlaidManager.shared.connectedItems
        var results: [SyncResult] = []

        for item in items {
            let result = await sync(item: item, context: context)
            results.append(result)
        }
        return results
    }

    func sync(item: PlaidConnectedItem, context: ModelContext) async -> SyncResult {
        do {
            let response = try await PlaidManager.shared.syncTransactions(for: item)

            var modifiedCount = 0
            var removedCount = 0

            // ── Added → shared reconciler (dedup + Option-C adoption + review flag),
            //    the same pipeline as Flinks. Category is resolved here and passed
            //    through so auto-categorisation is preserved.
            // Build the learned-category index ONCE for the whole batch.
            let catModel = SmartCategorizer.buildModel(in: context)
            var incoming: [IncomingBankTransaction] = []
            for plaidTx in response.added {
                guard let account = resolveAccount(plaidAccountId: plaidTx.account_id,
                                                   item: item, context: context) else { continue }
                let type: TransactionType = plaidTx.amount > 0 ? .expense : .income
                let payee = plaidTx.merchant_name ?? plaidTx.name
                // Prefer what the user usually does with this merchant; fall back to
                // Plaid's category keywords when the merchant is unknown.
                let category = catModel.suggest(payee: payee, type: type)
                    ?? matchCategory(plaidCategories: plaidTx.category ?? [], type: type, context: context)
                incoming.append(IncomingBankTransaction(
                    externalId: plaidTx.transaction_id,
                    accountKey: account.uuid,
                    isIncome: plaidTx.amount < 0,     // Plaid: negative = credit
                    amount: Decimal(abs(plaidTx.amount)),
                    date: parseDate(plaidTx.date) ?? .now,
                    payee: payee.isEmpty ? nil : payee,
                    note: "[Plaid] \(plaidTx.name)",
                    bankDescription: plaidTx.name,
                    category: category
                ))
            }
            let outcome = TransactionReconciler.reconcile(incoming, context: context)
            let addedCount      = outcome.added
            let reconciledCount = outcome.reconciled
            let flaggedCount    = outcome.flagged

            // ── Process modified transactions ─────────────────────────────
            for plaidTx in response.modified {
                if let existing = existingTransaction(plaidId: plaidTx.transaction_id, context: context) {
                    applyUpdate(plaidTx: plaidTx, to: existing, context: context)
                    modifiedCount += 1
                }
            }

            // ── Process removed transactions ──────────────────────────────
            for removed in response.removed {
                if let existing = existingTransaction(plaidId: removed.transaction_id, context: context) {
                    context.delete(existing)
                    removedCount += 1
                }
            }

            try? context.save()

            // Recalculate balance for all accounts touched by this sync
            let allAccounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
            allAccounts.forEach { $0.recalculateBalance() }

            // ── Balance anchor (first sync / long gap) or reconcile (recent) ──
            let discrepancies = await reconcileBalances(item: item, context: context)

            // Update cursor for next sync
            PlaidManager.shared.updateCursor(for: item.id, cursor: response.next_cursor)

            return SyncResult(itemId: item.id,
                               added: addedCount,
                               reconciled: reconciledCount,
                               flagged: flaggedCount,
                               modified: modifiedCount,
                               removed: removedCount,
                               details: outcome.details,
                               discrepancies: discrepancies,
                               error: nil)

        } catch PlaidError.reAuthRequired {
            // Mark item as needing re-auth — UI will show a banner
            return SyncResult(itemId: item.id,
                               added: 0, reconciled: 0, flagged: 0, modified: 0, removed: 0,
                               details: [],
                               discrepancies: [],
                               error: PlaidError.reAuthRequired(itemId: item.id))
        } catch {
            return SyncResult(itemId: item.id,
                               added: 0, reconciled: 0, flagged: 0, modified: 0, removed: 0,
                               details: [],
                               discrepancies: [],
                               error: error)
        }
    }

    // MARK: - Balance anchoring / reconciliation

    /// After importing transactions, reconcile each mapped account's balance with
    /// the real balance Plaid reports:
    ///  - first sync (lastBankSyncAt == nil) or gap > 30 days → silent (re)anchor
    ///    (`initialBalance` shifted so the computed balance equals `current`),
    ///  - otherwise → compare; a gap is real drift → surfaced as a discrepancy.
    /// Credit cards flip the sign (Plaid: amount owed positive; FinTrack: negative).
    private func reconcileBalances(item: PlaidConnectedItem,
                                   context: ModelContext) async -> [BalanceDiscrepancy] {
        guard let balances = try? await PlaidManager.shared.fetchBalances(for: item) else { return [] }
        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        var discrepancies: [BalanceDiscrepancy] = []
        let now = Date.now
        var didChange = false

        for accBal in balances.accounts {
            guard let meta = item.accounts.first(where: { $0.id == accBal.account_id }),
                  let ftId = meta.fintrackAccountId,
                  let account = accounts.first(where: { $0.uuid == ftId })
            else { continue }
            // Skip if Plaid reports a currency that differs from the account.
            if let cur = accBal.balances.iso_currency_code, cur != account.currency { continue }
            guard let currentRaw = accBal.balances.current else { continue }

            // Double → Decimal at 2 decimals; flip sign for credit cards.
            let declaredMag = Decimal(string: String(format: "%.2f", currentRaw)) ?? Decimal(currentRaw)
            let declared = account.type == .credit ? -declaredMag : declaredMag

            let daysSince = account.lastBankSyncAt.map { now.timeIntervalSince($0) / 86_400 }
            let anchor = account.lastBankSyncAt == nil || (daysSince ?? .infinity) > 30

            if anchor {
                OFXImportService.anchorBalance(to: declared, account: account)   // silent
            } else if let check = OFXImportService.balanceCheck(declaredBalance: declared,
                                                                declaredDate: now, account: account) {
                discrepancies.append(BalanceDiscrepancy(accountUuid: account.uuid,
                                                        accountName: account.name, check: check))
            }
            account.lastBankSyncAt = now
            didChange = true
        }
        if didChange { try? context.save() }
        return discrepancies
    }

    // MARK: - Transaction updates

    private func applyUpdate(plaidTx: PlaidTransaction,
                              to existing: Transaction,
                              context: ModelContext) {
        let isDebit   = plaidTx.amount > 0
        existing.type   = isDebit ? .expense : .income
        existing.amount = Decimal(abs(plaidTx.amount))
        existing.date   = parseDate(plaidTx.date) ?? existing.date
        existing.payee  = plaidTx.merchant_name ?? plaidTx.name
    }

    // MARK: - Helpers

    private func resolveAccount(plaidAccountId: String,
                                 item: PlaidConnectedItem,
                                 context: ModelContext) -> Account? {
        guard let meta = item.accounts.first(where: { $0.id == plaidAccountId }),
              let fintrackIdStr = meta.fintrackAccountId
        else { return nil }

        // Fetch the Account from SwiftData by its stable uuid.
        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        return accounts.first { $0.uuid == fintrackIdStr }
    }

    private func existingTransaction(plaidId: String, context: ModelContext) -> Transaction? {
        let all = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
        return all.first { $0.externalId == plaidId }
    }

    private func parseDate(_ str: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: str)
    }

    private func matchCategory(plaidCategories: [String],
                                type: TransactionType,
                                context: ModelContext) -> Category? {
        guard !plaidCategories.isEmpty else { return nil }

        let categories = (try? context.fetch(FetchDescriptor<Category>())) ?? []
        let applicable = categories.filter { $0.matches(type) }

        // Simple keyword mapping from Plaid's taxonomy
        let plaidJoined = plaidCategories.joined(separator: " ").lowercased()

        let mappings: [(keywords: [String], fr: String)] = [
            (["food", "restaurant", "dining"],          "Restaurant"),
            (["grocery", "supermarket", "alimentation"],"Alimentation"),
            (["transport", "taxi", "uber", "transit"],  "Transport"),
            (["transfer", "payment"],                    ""),
            (["travel", "airline", "hotel"],             "Voyage"),
            (["health", "medical", "pharmacy"],          "Santé"),
            (["entertainment", "recreation"],            "Loisirs"),
            (["clothing", "apparel"],                    "Vêtements"),
            (["education"],                              "Éducation"),
            (["bank", "fees", "service"],                "Frais bancaires"),
            (["income", "salary", "payroll"],            "Salaire"),
            (["interest", "dividend"],                   "Intérêts"),
        ]

        for mapping in mappings {
            let matched = mapping.keywords.contains { plaidJoined.contains($0) }
            if matched, !mapping.fr.isEmpty {
                return applicable.first { $0.name.lowercased() == mapping.fr.lowercased() }
            }
        }
        return nil
    }
}
