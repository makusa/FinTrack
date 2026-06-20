//
//  DuplicateReviewView.swift
//  FinTrack
//
//  Option-C review queue: bank-synced transactions flagged as possible
//  duplicates of a manual entry. The user either merges (adopt the bank
//  identity onto their manual row, drop the synced row) or keeps both.
//

import SwiftUI
import SwiftData

struct DuplicateReviewView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(LanguageManager.self) private var lang

    @Query(sort: \Transaction.date, order: .reverse)
    private var allTransactions: [Transaction]

    private var flagged: [Transaction] {
        allTransactions.filter { $0.needsReview }
    }

    var body: some View {
        NavigationStack {
            Group {
                if flagged.isEmpty {
                    ContentUnavailableView(
                        lang["review.empty.title"],
                        systemImage: "checkmark.seal",
                        description: Text(lang["review.empty.sub"])
                    )
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            Text(lang["review.explain"])
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal)
                            ForEach(flagged) { synced in
                                reviewCard(synced)
                            }
                        }
                        .padding(.vertical)
                    }
                }
            }
            .navigationTitle(lang["review.title"])
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(lang["action.close"]) { dismiss() }
                }
            }
        }
    }

    // MARK: - Card

    private func reviewCard(_ synced: Transaction) -> some View {
        let cands = candidates(for: synced)
        return VStack(alignment: .leading, spacing: 12) {
            // Bank transaction
            VStack(alignment: .leading, spacing: 4) {
                Label(lang["review.bankRow"], systemImage: "building.columns.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                HStack {
                    Text(synced.bankDescription ?? synced.payee ?? "—")
                        .font(.body.weight(.medium))
                    Spacer()
                    Text(amountText(synced))
                        .font(.body.weight(.semibold))
                }
                Text("\(synced.account?.name ?? "") · \(dateText(synced.date))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            if cands.isEmpty {
                Text(lang["review.noMatch"])
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button { keepBoth(synced) } label: {
                    Label(lang["review.keep"], systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            } else {
                Text(lang["review.yourEntry"])
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(cands) { m in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.payee ?? m.category?.localizedName ?? "—")
                                .font(.subheadline)
                            Text(dateText(m.date))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { merge(synced: synced, into: m) } label: {
                            Label(lang["review.merge"], systemImage: "arrow.triangle.merge")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                Button { keepBoth(synced) } label: {
                    Label(lang["review.keepBoth"], systemImage: "rectangle.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal)
    }

    // MARK: - Candidate derivation (same criteria as the sync-time matcher)

    private func candidates(for synced: Transaction) -> [Transaction] {
        guard let acc = synced.account else { return [] }
        let cal = Calendar.current
        return allTransactions.filter { m in
            m.externalId == nil
                && m.status != .skipped
                && m.account?.uuid == acc.uuid
                && m.type == synced.type
                && TransactionMatcher.amountsMatch(m.amount, synced.amount,
                                                   epsilon: TransactionMatcher.amountEpsilon)
                && TransactionMatcher.withinWindow(m.date, synced.date,
                                                   days: TransactionMatcher.dateWindowDays, calendar: cal)
        }
    }

    // MARK: - Actions

    /// Merge: adopt the bank identity onto the user's manual row, then drop the
    /// synced row. Removes the double-count; the surviving row keeps the user's
    /// category/note and becomes reconciled.
    private func merge(synced: Transaction, into manual: Transaction) {
        manual.externalId = synced.externalId
        manual.bankDescription = synced.bankDescription
        manual.status = .reconciled
        manual.needsReview = false
        let acc = synced.account ?? manual.account
        context.delete(synced)
        acc?.recalculateBalance()
        save()
    }

    /// Keep both: they are genuinely different transactions. Clear the flag; the
    /// synced row stays a normal reconciled bank row.
    private func keepBoth(_ synced: Transaction) {
        synced.needsReview = false
        save()
    }

    private func save() {
        do {
            try context.save()
        } catch {
            AppLogger.persistence.error("DuplicateReviewView save failed: \(error, privacy: .private)")
        }
    }

    // MARK: - Formatting

    private func amountText(_ tx: Transaction) -> String {
        let code = tx.account?.currency ?? Currencies.default
        let prefix = tx.type == .income ? "+" : "−"
        return prefix + tx.amount.formatted(asCurrency: code)
    }

    private func dateText(_ d: Date) -> String {
        d.formatted(.dateTime.day().month(.abbreviated).year())
    }
}
