//
//  UpcomingTransfersWidget.swift
//  FinTrack
//
//  Shows upcoming inter-account transfers:
//  - Recurring rules with isTransfer=true (next occurrence)
//  - Future one-time transactions with a transferPairId (expense leg only)
//
//  Sorted by due date ascending, capped at 5 items.
//

import SwiftUI
import SwiftData

struct UpcomingTransfersWidget: View {
    @Environment(LanguageManager.self) private var lang

    /// Active recurring transfer rules (isTransfer=true).
    let recurringTransfers: [RecurringTransaction]

    /// Future expense transactions that are part of a transfer pair.
    let futureTransferTx: [Transaction]

    // MARK: - Unified upcoming item

    private struct UpcomingTransfer: Identifiable {
        let id = UUID()
        let label: String           // description text
        let fromAccount: String
        let toAccount: String
        let amount: Decimal
        let currency: String
        let dueDate: Date
        let isRecurring: Bool
        let frequencyLabel: String?
    }

    private var items: [UpcomingTransfer] {
        var result: [UpcomingTransfer] = []
        let now  = Date()
        let cal  = Calendar.current
        let horizon = cal.date(byAdding: .day, value: 60, to: now) ?? now

        // From recurring rules
        for rule in recurringTransfers {
            guard let dst = rule.destinationAccount else { continue }
            let dueDate = rule.nextDueDate
            guard dueDate <= horizon else { continue }
            result.append(UpcomingTransfer(
                label: rule.title.isEmpty ? rule.displayTitle : rule.title,
                fromAccount: rule.account?.name ?? "?",
                toAccount: dst.name,
                amount: rule.amount,
                currency: rule.account?.currency ?? Currencies.default,
                dueDate: dueDate,
                isRecurring: true,
                frequencyLabel: rule.frequency.shortLabel
            ))
        }

        // From future one-time transfer transactions (expense leg)
        for tx in futureTransferTx {
            guard let payee = tx.payee else { continue }
            result.append(UpcomingTransfer(
                label: tx.note.isEmpty ? payee : tx.note,
                fromAccount: tx.account?.name ?? "?",
                toAccount: payee,
                amount: tx.amount,
                currency: tx.account?.currency ?? Currencies.default,
                dueDate: tx.date,
                isRecurring: false,
                frequencyLabel: nil
            ))
        }

        return result
            .sorted { $0.dueDate < $1.dueDate }
            .prefix(5)
            .map { $0 }
    }

    // MARK: - View

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text(lang["widget.transfers.title"])
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                NavigationLink(lang["action.seeAll"]) {
                    RecurrencesView()
                }
                .font(.caption)
            }
            .padding(.horizontal)

            if items.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                        transferRow(item)
                        if idx < items.count - 1 {
                            Divider().padding(.leading, 56)
                        }
                    }
                }
                .background(Color(.secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Row

    private func transferRow(_ item: UpcomingTransfer) -> some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.tint.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: item.isRecurring
                      ? "arrow.clockwise.circle.fill"
                      : "arrow.left.arrow.right.circle.fill")
                    .foregroundStyle(Color.tint)
                    .font(.system(size: 18))
            }

            // Accounts + label
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(item.fromAccount)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(item.toAccount)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                }
                HStack(spacing: 4) {
                    if item.isRecurring, let freq = item.frequencyLabel {
                        Label(freq, systemImage: "arrow.clockwise")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Label(lang["transfer.title"], systemImage: "arrow.left.arrow.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // Amount + due date
            VStack(alignment: .trailing, spacing: 3) {
                Text(item.amount.formatted(asCurrency: item.currency))
                    .font(.callout.weight(.semibold))
                Text(dueDateLabel(for: item.dueDate))
                    .font(.caption2)
                    .foregroundStyle(dueDateColor(for: item.dueDate))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.left.arrow.right.circle")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(lang["widget.transfers.empty"])
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    // MARK: - Helpers

    private func dueDateLabel(for date: Date) -> String {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: .now),
                                               to: cal.startOfDay(for: date)).day ?? 0
        switch days {
        case 0:       return lang["recurring.dueToday"]
        case 1:       return lang["recurring.dueTomorrow"]
        case ..<0:    return lang["recurring.overdue"]
        default:      return lang.f("recurring.dueInDays", days)
        }
    }

    private func dueDateColor(for date: Date) -> Color {
        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: .now),
            to: Calendar.current.startOfDay(for: date)
        ).day ?? 0
        if days < 0  { return .red }
        if days <= 3 { return .orange }
        return .secondary
    }
}
