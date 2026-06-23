//
//  RecurrencesView.swift
//  FinTrack
//

import SwiftUI
import SwiftData

struct RecurrencesView: View {
    @Environment(\.modelContext) private var context
    @Environment(LanguageManager.self) private var lang
    @Environment(EntitlementManager.self) private var entitlements

    @Query(sort: \RecurringTransaction.nextDueDate, order: .forward)
    private var allRules: [RecurringTransaction]

    @State private var showAdd = false
    @State private var showInactive = false
    @State private var showDeleteScopeConfirm = false
    @State private var pendingDeleteRule: RecurringTransaction?

    /// True when a free-tier user has reached the 5-rule cap.
    private var isAtFreeLimit: Bool {
        !entitlements.hasPaidTier && allRules.count >= FinTrackLimit.freeMaxRecurring
    }

    private var activeRules: [RecurringTransaction] {
        allRules.filter { $0.isActive }
    }
    private var inactiveRules: [RecurringTransaction] {
        allRules.filter { !$0.isActive }
    }

    var body: some View {
        List {
            if activeRules.isEmpty && inactiveRules.isEmpty {
                emptyState
            } else {
                if !activeRules.isEmpty {
                    Section(lang.f("recurring.active", activeRules.count)) {
                        ForEach(activeRules) { rule in
                            NavigationLink {
                                AddEditRecurringTransactionView(mode: .edit(rule))
                            } label: {
                                RecurringTransactionRow(rule: rule)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    delete(rule)
                                } label: {
                                    Label(lang["action.delete"], systemImage: "trash")
                                }
                                Button {
                                    toggleActive(rule)
                                } label: {
                                    Label(lang["action.pause"], systemImage: "pause.circle")
                                }
                                .tint(.orange)
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    RecurringTransactionManager.postNow(rule, context: context)
                                    rescheduleNotifications()
                                } label: {
                                    Label(lang["action.generateNow"], systemImage: "bolt.fill")
                                }
                                .tint(.blue)
                            }
                        }
                    }
                }

                if !inactiveRules.isEmpty {
                    Section {
                        DisclosureGroup(isExpanded: $showInactive) {
                            ForEach(inactiveRules) { rule in
                                NavigationLink {
                                    AddEditRecurringTransactionView(mode: .edit(rule))
                                } label: {
                                    RecurringTransactionRow(rule: rule)
                                        .opacity(0.5)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        delete(rule)
                                    } label: {
                                        Label(lang["action.delete"], systemImage: "trash")
                                    }
                                    Button {
                                        toggleActive(rule)
                                    } label: {
                                        Label(lang["action.resume"], systemImage: "play.circle")
                                    }
                                    .tint(.green)
                                }
                            }
                        } label: {
                            Text(lang.f("recurring.paused", inactiveRules.count))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(lang["recurring.title"])
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAdd = true
                } label: {
                    Image(systemName: "plus.circle.fill").font(.title3)
                }
                .disabled(isAtFreeLimit)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isAtFreeLimit {
                freeCapBanner
            }
        }
        .sheet(isPresented: $showAdd) {
            if isAtFreeLimit {
                NavigationStack {
                    ProGateView(feature: .recurring)
                        .environment(entitlements)
                }
            } else {
                AddEditRecurringTransactionView(mode: .create)
            }
        }
        .confirmationDialog(lang["recurring.deleteScope.title"],
                            isPresented: $showDeleteScopeConfirm,
                            titleVisibility: .visible,
                            presenting: pendingDeleteRule) { rule in
            Button(lang["recurring.scope.all"], role: .destructive) {
                RecurringTransactionManager.deleteRule(rule, scope: .allTransactions, context: context)
                rescheduleNotifications()
            }
            Button(lang["recurring.scope.future"]) {
                RecurringTransactionManager.deleteRule(rule, scope: .futureOnly, context: context)
                rescheduleNotifications()
            }
            Button(lang["action.cancel"], role: .cancel) {}
        } message: { _ in
            Text(lang["recurring.deleteScope.message"])
        }
    }

    // MARK: - Free tier cap banner

    private var freeCapBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(lang["recurring.free.cap.title"])
                    .font(.callout.weight(.semibold))
                Text(lang["recurring.free.cap.subtitle"])
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            NavigationLink {
                SubscriptionView()
                    .environment(entitlements)
            } label: {
                Text(lang["entitlement.pro.cta"])
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.orange.opacity(0.15), in: Capsule())
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.2.squarepath")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
                .padding(.top, 32)
            Text(lang["recurring.empty.title"])
                .font(.headline)
            Text(lang["recurring.empty.sub"])
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    // MARK: - Actions

    private func toggleActive(_ rule: RecurringTransaction) {
        rule.isActive.toggle()
        try? context.save()
        rescheduleNotifications()
    }

    private func delete(_ rule: RecurringTransaction) {
        // Historique généré → proposer la portée (toutes vs à venir).
        // Sinon, aucune transaction concernée : suppression directe de la règle.
        if RecurringTransactionManager.hasGeneratedTransactions(rule) {
            pendingDeleteRule = rule
            showDeleteScopeConfirm = true
        } else {
            context.delete(rule)
            try? context.save()
            rescheduleNotifications()
        }
    }

    /// Réaligne toutes les notifications planifiées sur l'état actuel des données
    /// (annule puis reconstruit) — après suppression, pause/reprise, génération.
    private func rescheduleNotifications() {
        let ctx = context
        Task { await NotificationManager.shared.scheduleAll(context: ctx) }
    }
}

// MARK: - Row component

struct RecurringTransactionRow: View {
    let rule: RecurringTransaction

    private var iconColor: Color {
        if let hex = rule.category?.colorHex { return Color(hex: hex) }
        return rule.type == .income ? .green : .secondary
    }

    private var iconName: String {
        rule.category?.iconSystemName ?? (rule.type == .income ? "arrow.down.circle" : "arrow.up.circle")
    }

    private var amountText: String {
        let code = rule.account?.currency ?? Currencies.default
        let prefix = rule.type == .income ? "+" : "−"
        return prefix + rule.amount.formatted(asCurrency: code)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Category icon
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 42, height: 42)
                Image(systemName: iconName)
                    .foregroundStyle(iconColor)
                    .font(.system(size: 18, weight: .semibold))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(rule.displayTitle)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    // Frequency badge
                    Text(rule.frequency.label)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(.tertiarySystemBackground), in: Capsule())
                        .foregroundStyle(.secondary)
                    if let acc = rule.account {
                        Text("· \(acc.name)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(amountText)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(rule.type == .income ? .green : .primary)

                // Due date with colour cue
                Text(rule.dueDateLabel)
                    .font(.caption2)
                    .foregroundStyle(dueDateForeground)
            }
        }
        .padding(.vertical, 3)
    }

    private var dueDateForeground: Color {
        switch rule.dueDateColor {
        case .overdue: return .red
        case .soon:    return .orange
        case .normal:  return .secondary
        }
    }
}

#Preview {
    NavigationStack {
        RecurrencesView()
            .modelContainer(for: [Account.self, Transaction.self, Category.self,
                                   RecurringTransaction.self], inMemory: true)
    }
}
