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

    struct SyncResult {
        let itemId:   String
        let added:    Int
        let modified: Int
        let removed:  Int
        let error:    Error?
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

            var addedCount   = 0
            var modifiedCount = 0
            var removedCount = 0

            // ── Process added transactions ────────────────────────────────
            for plaidTx in response.added {
                guard let fintrackAccount = resolveAccount(
                    plaidAccountId: plaidTx.account_id,
                    item: item,
                    context: context
                ) else { continue }

                // Check for duplicate
                if existingTransaction(plaidId: plaidTx.transaction_id, context: context) != nil {
                    continue
                }

                let tx = buildTransaction(from: plaidTx,
                                          account: fintrackAccount,
                                          context: context)
                context.insert(tx)
                addedCount += 1
            }

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

            // Update cursor for next sync
            PlaidManager.shared.updateCursor(for: item.id, cursor: response.next_cursor)

            return SyncResult(itemId: item.id,
                               added: addedCount,
                               modified: modifiedCount,
                               removed: removedCount,
                               error: nil)

        } catch PlaidError.reAuthRequired {
            // Mark item as needing re-auth — UI will show a banner
            return SyncResult(itemId: item.id,
                               added: 0, modified: 0, removed: 0,
                               error: PlaidError.reAuthRequired(itemId: item.id))
        } catch {
            return SyncResult(itemId: item.id,
                               added: 0, modified: 0, removed: 0,
                               error: error)
        }
    }

    // MARK: - Transaction building

    private func buildTransaction(from plaidTx: PlaidTransaction,
                                  account: Account,
                                  context: ModelContext) -> Transaction {
        // Plaid: positive amount = money leaving account (debit)
        //        negative amount = money entering account (credit)
        let isDebit  = plaidTx.amount > 0
        let type:    TransactionType = isDebit ? .expense : .income
        let absAmount = Decimal(abs(plaidTx.amount))

        let date = parseDate(plaidTx.date) ?? .now

        let payee = plaidTx.merchant_name ?? plaidTx.name

        // Try to match a FinTrack category
        let category = matchCategory(plaidCategories: plaidTx.category ?? [],
                                     type: type,
                                     context: context)

        let tx = Transaction(
            amount:   absAmount,
            type:     type,
            date:     date,
            account:  account,
            category: category,
            note:     "[Plaid] \(plaidTx.name)",
            payee:    payee.isEmpty ? nil : payee
        )
        // Tag with Plaid transaction ID for deduplication + updates
        tx.plaidTransactionId = plaidTx.transaction_id

        return tx
    }

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
              let fintrackIdStr = meta.fintrackAccountId,
              let uuid = UUID(uuidString: fintrackIdStr)
        else { return nil }

        // Fetch the Account from SwiftData by UUID (stored in Account.name — we match by persistent ID)
        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        return accounts.first { $0.persistentModelID.hashValue == uuid.hashValue }
    }

    private func existingTransaction(plaidId: String, context: ModelContext) -> Transaction? {
        let all = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
        return all.first { $0.plaidTransactionId == plaidId }
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
