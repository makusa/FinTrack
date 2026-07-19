//
//  BudgetsView.swift
//  FinTrack
//

import SwiftUI
import SwiftData
import Charts

struct BudgetsView: View {
    @Environment(LanguageManager.self) private var lang
    @Environment(\.modelContext) private var context
    @Environment(EntitlementManager.self) private var entitlements

    @Query(filter: #Predicate<Budget> { $0.isActive },
           sort: [SortDescriptor(\Budget.sortIndex, order: .forward),
                  SortDescriptor(\Budget.createdAt, order: .forward)])
    private var activeBudgets: [Budget]

    @Query(filter: #Predicate<Budget> { !$0.isActive }, sort: \Budget.createdAt)
    private var archivedBudgets: [Budget]

    @Query(sort: \Transaction.date, order: .reverse)
    private var allTransactions: [Transaction]

    @State private var showAdd          = false
    @State private var showArchived     = false

    private var isAtFreeLimit: Bool {
        !entitlements.hasPaidTier && activeBudgets.count >= FinTrackLimit.freeMaxBudgets
    }

    private var statuses: [BudgetStatus] {
        activeBudgets.map { BudgetStatus(budget: $0, spent: BudgetCalculator.spent(for: $0, in: allTransactions)) }
    }

    var body: some View {
        Group {
            if activeBudgets.isEmpty && archivedBudgets.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .navigationTitle(lang["budget.title"])
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if activeBudgets.count > 1 { EditButton() }
            }
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
            if isAtFreeLimit { freeCapBanner }
        }
        .sheet(isPresented: $showAdd) {
            if isAtFreeLimit {
                NavigationStack {
                    ProGateView(feature: .budgets)
                        .environment(entitlements)
                }
            } else {
                AddEditBudgetView(mode: .create)
            }
        }
    }

    // MARK: - Free tier cap banner

    private var freeCapBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(lang["budget.free.cap.title"])
                    .font(.callout.weight(.semibold))
                Text(lang["budget.free.cap.subtitle"])
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            NavigationLink {
                SubscriptionView().environment(entitlements)
            } label: {
                Text(lang["entitlement.pro.cta"])
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color.orange.opacity(0.15), in: Capsule())
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text(lang["budget.empty.title"])
                .font(.title2.weight(.semibold))
            Text(lang["budget.empty.sub"])
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            Button {
                showAdd = true
            } label: {
                Label(lang["budget.create"], systemImage: "plus")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - List

    private var list: some View {
        List {
            // Over-budget alert banner
            let overBudget = statuses.filter { $0.isOverBudget }
            if !overBudget.isEmpty {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(lang.f("budget.over.banner", overBudget.count))
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.red)
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Color.red.opacity(0.08))
            }

            // Active budgets
            Section(lang["budget.active"]) {
                ForEach(statuses) { status in
                    NavigationLink {
                        BudgetDetailView(budget: status.budget, allTransactions: allTransactions)
                    } label: {
                        BudgetRow(status: status)
                    }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                deleteBudget(status.budget)
                            } label: { Label(lang["action.delete"], systemImage: "trash") }

                            Button {
                                status.budget.isActive = false
                                try? context.save()
                            } label: {
                                Label(lang["action.archive"], systemImage: "archivebox")
                            }
                            .tint(.orange)
                        }
                }
                .onMove(perform: moveBudgets)
                if !isAtFreeLimit {
                    Button {
                        showAdd = true
                    } label: {
                        Label(lang["budget.add"], systemImage: "plus")
                    }
                }
            }

            // Archived budgets
            if !archivedBudgets.isEmpty {
                Section {
                    DisclosureGroup(isExpanded: $showArchived) {
                        ForEach(archivedBudgets) { b in
                            HStack {
                                ZStack {
                                    Circle().fill(Color(hex: b.colorHex).opacity(0.15)).frame(width: 36, height: 36)
                                    Image(systemName: b.iconSystemName)
                                        .foregroundStyle(Color(hex: b.colorHex))
                                }
                                Text(b.name).foregroundStyle(.secondary)
                                Spacer()
                                Button(lang["action.resume"]) {
                                    b.isActive = true
                                    try? context.save()
                                }
                                .font(.caption)
                                .buttonStyle(.bordered)
                            }
                            .opacity(0.7)
                        }
                    } label: {
                        Text(lang.f("budget.archived", archivedBudgets.count))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func deleteBudget(_ b: Budget) {
        context.delete(b)
        try? context.save()
    }

    /// Réordonne les budgets actifs et persiste le nouvel ordre dans `sortIndex`.
    private func moveBudgets(from source: IndexSet, to destination: Int) {
        var reordered = activeBudgets
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, b) in reordered.enumerated() {
            b.sortIndex = index
        }
        try? context.save()
    }
}

// MARK: - BudgetRow

struct BudgetRow: View {
    @Environment(LanguageManager.self) private var lang
    let status: BudgetStatus

    private var budget: Budget { status.budget }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header row
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color(hex: budget.colorHex).opacity(0.15))
                        .frame(width: 38, height: 38)
                    Image(systemName: budget.iconSystemName)
                        .foregroundStyle(Color(hex: budget.colorHex))
                        .font(.system(size: 16, weight: .semibold))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(budget.name)
                        .font(.body.weight(.medium))
                    Text(budget.categoriesLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(status.spent.formatted(asCurrency: budget.currency))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(status.progressColor)
                    Text("/ \(budget.limitAmount.formatted(asCurrency: budget.currency))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(height: 7)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(status.progressColor)
                        .frame(width: min(geo.size.width * CGFloat(min(status.fraction, 1.0)), geo.size.width), height: 7)
                        .animation(.easeOut(duration: 0.4), value: status.fraction)
                }
            }
            .frame(height: 7)

            // Footer: % + remaining + period
            HStack {
                statusBadge
                Spacer()
                Text(budget.period.currentPeriodLabel())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var statusBadge: some View {
        if status.isOverBudget {
            Label(
                "\(lang["budget.over"]) \(status.remaining.magnitude.formatted(asCurrency: budget.currency))",
                systemImage: "exclamationmark.circle.fill"
            )
            .font(.caption.weight(.medium))
            .foregroundStyle(.red)
        } else if status.isNearLimit {
            Label(
                "\(String(format: "%.0f", status.fraction * 100))%",
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.caption.weight(.medium))
            .foregroundStyle(.orange)
        } else {
            Text(String(format: "%.0f%%", min(status.fraction * 100, 100)))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - BudgetStatus Identifiable

extension BudgetStatus: Identifiable {
    var id: PersistentIdentifier { budget.persistentModelID }
}
