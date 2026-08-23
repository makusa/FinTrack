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

    // Les paiements de prêt/marge sont des générateurs internes (gérés via leurs
    // propres écrans) : on les exclut de la liste des récurrences génériques.
    @Query(filter: #Predicate<RecurringTransaction> { !$0.isLoanPayment && !$0.isCreditLinePayment },
           sort: \RecurringTransaction.nextDueDate, order: .forward)
    private var allRules: [RecurringTransaction]

    @State private var showAdd = false
    @State private var showInactive = false
    @State private var showDeleteScopeConfirm = false
    @State private var pendingDeleteRule: RecurringTransaction?
    @State private var showReactivateConfirm = false
    @State private var pendingReactivateRule: RecurringTransaction?
    @State private var suggestions: [RecurrenceDetector.Suggestion] = []
    @State private var dismissedSuggestions: Set<String> = []
    private let dismissedKey = "recurring.dismissedSuggestions"

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
            suggestionsSection
            if activeRules.isEmpty && inactiveRules.isEmpty && suggestions.isEmpty {
                emptyState
            } else {
                if !activeRules.isEmpty {
                    Section(lang.f("recurring.active", activeRules.count)) {
                        ForEach(activeRules) { rule in
                            NavigationLink {
                                LazyView(AddEditRecurringTransactionView(mode: .edit(rule)))
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
                                Button {
                                    RecurringTransactionManager.skipNextOccurrence(rule)
                                    try? context.save()
                                    rescheduleNotifications()
                                } label: {
                                    Label(lang["recurring.skipNext"], systemImage: "forward.end.fill")
                                }
                                .tint(.orange)
                            }
                        }
                    }
                }

                if !inactiveRules.isEmpty {
                    Section {
                        DisclosureGroup(isExpanded: $showInactive) {
                            ForEach(inactiveRules) { rule in
                                NavigationLink {
                                    LazyView(AddEditRecurringTransactionView(mode: .edit(rule)))
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
        .onAppear { refreshSuggestions() }
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
        .confirmationDialog(lang["recurring.reactivate.title"],
                            isPresented: $showReactivateConfirm,
                            titleVisibility: .visible,
                            presenting: pendingReactivateRule) { rule in
            Button(lang["recurring.reactivate.catchUp"]) { reactivate(rule, catchUp: true) }
            Button(lang["recurring.reactivate.skip"]) { reactivate(rule, catchUp: false) }
            Button(lang["action.cancel"], role: .cancel) {}
        } message: { _ in
            Text(lang["recurring.reactivate.message"])
        }
    }

    // MARK: - Free tier cap banner

    // MARK: - Suggestions (on-device recurrence detection)

    @ViewBuilder
    private var suggestionsSection: some View {
        if !suggestions.isEmpty {
            Section {
                ForEach(suggestions) { s in
                    suggestionRow(s)
                }
            } header: {
                Label(lang["recurring.suggestions"], systemImage: "sparkles")
            } footer: {
                Text(lang["recurring.suggestions.footer"])
            }
        }
    }

    private func suggestionRow(_ s: RecurrenceDetector.Suggestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: s.frequency.iconSystemName)
                    .foregroundStyle(.purple)
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.payee).font(.callout.weight(.medium)).lineLimit(1)
                    Text("\(s.amount.formatted(asCurrency: s.currency)) · \(s.frequency.label)")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(lang.f("recurring.suggestion.detected", s.count))
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
            }
            HStack {
                Button {
                    createRule(from: s)
                } label: {
                    Text(lang["action.create"]).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                Button {
                    ignore(s)
                } label: {
                    Text(lang["action.ignore"]).frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    private func refreshSuggestions() {
        guard entitlements.hasPaidTier else { suggestions = []; return }
        dismissedSuggestions = Set(UserDefaults.standard.stringArray(forKey: dismissedKey) ?? [])
        suggestions = RecurrenceDetector.detect(in: context, dismissed: dismissedSuggestions)
    }

    private func createRule(from s: RecurrenceDetector.Suggestion) {
        let rule = RecurringTransaction(
            amount: s.amount,
            type: s.type,
            frequency: s.frequency,
            startDate: s.lastDate,
            account: s.account,
            category: s.category,
            payee: s.payee
        )
        // Advance the next due date into the future — past occurrences already exist
        // as real transactions, so we must not regenerate them.
        var next = s.frequency.nextDate(after: s.lastDate)
        while next < Date.now { next = s.frequency.nextDate(after: next) }
        rule.nextDueDate = next
        context.insert(rule)
        try? context.save()
        suggestions.removeAll { $0.id == s.id }
        rescheduleNotifications()
    }

    private func ignore(_ s: RecurrenceDetector.Suggestion) {
        dismissedSuggestions.insert(s.id)
        UserDefaults.standard.set(Array(dismissedSuggestions), forKey: dismissedKey)
        suggestions.removeAll { $0.id == s.id }
    }

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
        if rule.isActive {
            // Mise en pause : gel simple (plus de génération ni de rappel).
            rule.isActive = false
            try? context.save()
            rescheduleNotifications()
        } else if RecurringTransactionManager.hasMissedOccurrences(rule) {
            // Reprise avec échéances manquées : demander rattrapage ou reprise nette.
            pendingReactivateRule = rule
            showReactivateConfirm = true
        } else {
            // Reprise sans échéance manquée : réactivation directe.
            rule.isActive = true
            try? context.save()
            rescheduleNotifications()
        }
    }

    private func reactivate(_ rule: RecurringTransaction, catchUp: Bool) {
        if !catchUp {
            // Repartir à la prochaine échéance : ignorer les occurrences passées.
            RecurringTransactionManager.skipMissedOccurrences(rule)
        }
        rule.isActive = true
        try? context.save()
        // Génère immédiatement ce qui est dû (rattrapage si catchUp), recalcule, sauvegarde.
        RecurringTransactionManager.applyPending(context: context)
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

// MARK: - Lazy navigation destination

/// Defers building `Content` until this view is actually rendered. Wrapping a heavy
/// NavigationLink destination in `LazyView` stops the parent List from resolving the
/// destination's (very deep) view type eagerly at render time — which was freezing
/// the recurrences list the moment a first rule (and thus a first link) appeared.
struct LazyView<Content: View>: View {
    private let build: () -> Content
    init(_ build: @autoclosure @escaping () -> Content) { self.build = build }
    var body: Content { build() }
}
