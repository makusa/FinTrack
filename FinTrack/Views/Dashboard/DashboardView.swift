//
//  DashboardView.swift
//  FinTrack
//
//  Driven by DashboardConfigManager — widgets are shown in the user's
//  chosen order and can be hidden / reordered from DashboardLibraryView.
//

import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var context
    @Environment(LanguageManager.self) private var lang
    @Environment(EntitlementManager.self) private var entitlements
    @Environment(ExchangeRateManager.self) private var rates

    @Query(filter: #Predicate<Account> { !$0.isArchived },
           sort: \Account.createdAt, order: .forward)
    private var accounts: [Account]

    @Query(sort: \Transaction.date, order: .reverse)
    private var allTransactions: [Transaction]

    @Query(filter: #Predicate<CreditLine> { $0.isActive },
           sort: \CreditLine.createdAt, order: .forward)
    private var activeCreditLines: [CreditLine]

    @Query(filter: #Predicate<Loan> { $0.isActive },
           sort: \Loan.createdAt, order: .forward)
    private var activeLoans: [Loan]

    @Query(filter: #Predicate<RecurringTransaction> { $0.isActive },
           sort: \RecurringTransaction.nextDueDate, order: .forward)
    private var activeRecurring: [RecurringTransaction]

    // Future one-time transfer transactions (expense leg, next 60 days)
    @Query(filter: #Predicate<Transaction> { $0.transferPairId != nil && $0.typeRaw == "expense" },
           sort: \Transaction.date, order: .forward)
    private var futureTransferExpenses: [Transaction]

    @State private var config           = DashboardConfigManager.shared
    @State private var showAddTransaction = false
    @State private var showAddAccount     = false
    @State private var showAddTransfer    = false
    @State private var showLibrary        = false

    // MARK: - Derived data

    private var totalsByCurrency: [(currency: String, total: Decimal)] {
        Dictionary(grouping: accounts, by: \.currency)
            .map { (currency: $0.key, total: $0.value.reduce(Decimal(0)) { $0 + $1.balance }) }
            .sorted { $0.currency < $1.currency }
    }

    private var recentTransactions: [Transaction]    { Array(allTransactions.prefix(10)) }
    private var recurringTransfers: [RecurringTransaction] {
        let horizon = Calendar.current.date(byAdding: .day, value: 60, to: .now) ?? .now
        return activeRecurring.filter { $0.isTransfer && $0.nextDueDate <= horizon }
    }

    private var upcomingTransferTx: [Transaction] {
        let now     = Date()
        let horizon = Calendar.current.date(byAdding: .day, value: 60, to: now) ?? now
        return futureTransferExpenses.filter { $0.date > now && $0.date <= horizon }
    }

    private var upcomingRecurrences: [RecurringTransaction] {
        let horizon = Calendar.current.date(byAdding: .day, value: 30, to: .now) ?? .now
        return Array(activeRecurring.filter { $0.nextDueDate <= horizon }.prefix(5))
    }

    private var dominantCurrency: String? {
        Dictionary(grouping: accounts, by: \.currency).mapValues(\.count)
            .max(by: { $0.value < $1.value })?.key
    }

    private var thisMonthSummary: (income: Decimal, expense: Decimal, currency: String?) {
        guard let cur = dominantCurrency else { return (0, 0, nil) }
        let start = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
        let filtered = allTransactions.filter { $0.date >= start && $0.account?.currency == cur }
        let income  = filtered.filter { $0.type == .income  }.reduce(Decimal(0)) { $0 + $1.amount }
        let expense = filtered.filter { $0.type == .expense }.reduce(Decimal(0)) { $0 + $1.amount }
        return (income, expense, cur)
    }

    private var convertedGlobalTotal: Decimal {
        totalsByCurrency.reduce(Decimal(0)) {
            $0 + rates.convert($1.total, from: $1.currency, to: rates.displayCurrency)
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if accounts.isEmpty { emptyState }
                else { populated }
            }
            .navigationTitle(lang["dashboard.title"])
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showLibrary = true
                    } label: {
                        Image(systemName: "square.grid.2x2")
                            .font(.body)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showAddTransaction = true } label: {
                            Label(lang["tx.create"], systemImage: "plus")
                        }
                        Button { showAddTransfer = true } label: {
                            Label(lang["transfer.create"], systemImage: "arrow.left.arrow.right")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill").font(.title3)
                    }
                    .disabled(accounts.isEmpty)
                }
            }
            .sheet(isPresented: $showAddTransaction) {
                NavigationStack { AddEditTransactionView(mode: .create) }
            }
            .sheet(isPresented: $showAddTransfer) { AddTransferView() }
            .sheet(isPresented: $showAddAccount)   { AddEditAccountView(mode: .create) }
            .sheet(isPresented: $showLibrary)      { DashboardLibraryView() }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "building.columns")
                .font(.system(size: 56)).foregroundStyle(.tint)
            Text(lang["dashboard.welcome.title"])
                .font(.title2.weight(.semibold))
            Text(lang["dashboard.welcome.subtitle"])
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            Button {
                showAddAccount = true
            } label: {
                Label(lang["dashboard.welcome.cta"], systemImage: "plus")
                    .font(.body.weight(.semibold))
                    .padding(.horizontal, 20).padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent).padding(.top, 8)
            Spacer(); Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Populated (widget-driven)

    private var populated: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(config.enabled) { widgetId in
                    widgetView(for: widgetId)
                }
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Widget dispatcher

    @ViewBuilder
    private func widgetView(for id: DashboardWidgetID) -> some View {
        // Pro-only widgets are hidden for Courant users
        if id.requiresPro && !entitlements.hasPro {
            proTeaser(for: id)
            return
        }
        switch id {
        case .globalBalance:
            globalBalanceWidget

        case .accountsCarousel:
            accountsCarouselWidget

        case .monthSummary:
            monthSummaryWidget

        case .loans:
            if !activeLoans.isEmpty { loanWidget }

        case .creditLines:
            if !activeCreditLines.isEmpty { creditLineWidget }

        case .cashFlow:
            if let cur = dominantCurrency {
                BudgetDashboardSection(
                    recurring: activeRecurring,
                    loans: activeLoans,
                    currency: cur
                )
                .id("cashFlow")
            }

        case .budgets:
            if let cur = dominantCurrency {
                // BudgetCard is included inside BudgetDashboardSection; here we
                // want just the budgets card — injected via budgetSection helper
                budgetSectionWidget(currency: cur)
            }

        case .savingsGoals:
            if let cur = dominantCurrency {
                savingsWidget(currency: cur)
            }

        case .balanceProjection, .incomeVsExpenses, .categoryBreakdown:
            if let cur = dominantCurrency {
                AnalyticsDashboardSection(
                    accounts: accounts,
                    transactions: allTransactions,
                    activeRecurring: activeRecurring,
                    currency: cur,
                    visibleWidgets: analyticsWidgets
                )
                .id("analytics")
            }

        case .upcomingRecurring:
            if !upcomingRecurrences.isEmpty { upcomingWidget }

        case .recentTransactions:
            recentWidget

        case .netWorth:
            NetWorthWidget(
                accounts: totalsByCurrency,
                loans: activeLoans,
                creditLines: activeCreditLines
            )

        case .exchangeRates:
            ExchangeRateWidget(
                accountCurrencies: Array(Set(accounts.map { $0.currency }))
            )

        case .upcomingTransfers:
            UpcomingTransfersWidget(
                recurringTransfers: recurringTransfers,
                futureTransferTx: upcomingTransferTx
            )
        }
    }

    // Analytics widgets that are currently enabled
    private var analyticsWidgets: Set<DashboardWidgetID> {
        Set(config.enabled.filter {
            $0 == .balanceProjection || $0 == .incomeVsExpenses || $0 == .categoryBreakdown
        })
    }

    // MARK: - Pro teaser (shown when Courant user has a pro-only widget in their layout)

    private func proTeaser(for id: DashboardWidgetID) -> some View {
        HStack(spacing: 12) {
            Image(systemName: id.icon)
                .font(.title3)
                .foregroundStyle(.orange)
                .frame(width: 36, height: 36)
                .background(Color.orange.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(id.label)
                    .font(.callout.weight(.semibold))
                Text(lang["entitlement.pro.teaser"])
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            NavigationLink {
                SubscriptionView().environment(entitlements)
            } label: {
                Text(lang["entitlement.pro.cta"])
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.orange.opacity(0.15), in: Capsule())
                    .foregroundStyle(.orange)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.orange.opacity(0.2)))
        .padding(.horizontal)
    }

    // MARK: - Individual widgets

    private var globalBalanceWidget: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(lang["dashboard.globalBalance"])
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(convertedGlobalTotal.formatted(asCurrency: rates.displayCurrency))
                            .font(.title.weight(.bold))
                            .foregroundStyle(convertedGlobalTotal >= 0 ? Color.primary : Color.red)
                            .minimumScaleFactor(0.7).lineLimit(1)
                        if rates.isLoading {
                            Label(lang["fx.loading"], systemImage: "arrow.triangle.2.circlepath")
                                .font(.caption2).foregroundStyle(.secondary)
                        } else if let updated = rates.lastUpdated {
                            Text(lang.f("fx.updated",
                                        updated.appFormattedRelative()))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(rates.isLoading ? Color.orange : Color(.tertiaryLabel))
                        .rotationEffect(.degrees(rates.isLoading ? 360 : 0))
                        .animation(rates.isLoading
                                   ? .linear(duration: 1).repeatForever(autoreverses: false)
                                   : .default, value: rates.isLoading)
                        .onTapGesture { Task { await rates.refresh() } }
                }
                Divider()
                ForEach(totalsByCurrency, id: \.currency) { row in
                    HStack {
                        Text(Currencies.info(for: row.currency).nameFR)
                            .font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(row.total.formatted(asCurrency: row.currency))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(row.total >= 0 ? Color.primary : Color.red)
                            if row.currency != rates.displayCurrency,
                               let label = rates.convertedLabel(row.total,
                                    from: row.currency, to: rates.displayCurrency) {
                                Text(label).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(16)
            .background(Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
        }
    }

    private var accountsCarouselWidget: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(lang["dashboard.myAccounts"])
                    .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                NavigationLink(lang["action.seeAll"]) { AccountsView() }
                    .font(.caption)
            }
            .padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(accounts) { account in
                        NavigationLink { AccountDetailView(account: account) } label: {
                            BalanceCard(account: account)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    @ViewBuilder
    private var monthSummaryWidget: some View {
        let summary = thisMonthSummary
        if let cur = summary.currency {
            VStack(alignment: .leading, spacing: 8) {
                Text(lang["dashboard.thisMonth"] + " (\(cur))")
                    .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                    .padding(.horizontal)
                HStack(spacing: 12) {
                    summaryTile(lang["label.incomes"],  value: summary.income,
                                currency: cur, color: .green,
                                icon: "arrow.down.left.circle.fill")
                    summaryTile(lang["label.expenses"], value: summary.expense,
                                currency: cur, color: .red,
                                icon: "arrow.up.right.circle.fill")
                }
                .padding(.horizontal)
            }
        }
    }

    private func summaryTile(_ title: String, value: Decimal, currency: String,
                              color: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundStyle(color)
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Text(value.formatted(asCurrency: currency))
                .font(.headline.weight(.semibold))
                .minimumScaleFactor(0.7).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var loanWidget: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(lang["dashboard.myLoans"])
                    .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                NavigationLink(lang["action.seeAll"]) { LoansView() }.font(.caption)
            }
            .padding(.horizontal)
            VStack(spacing: 0) {
                ForEach(Array(activeLoans.prefix(3).enumerated()), id: \.element.id) { idx, loan in
                    NavigationLink { LoanDetailView(loan: loan) } label: {
                        let calc = loan.calculator
                        HStack(spacing: 12) {
                            ZStack {
                                Circle().fill(Color.accentColor.opacity(0.12)).frame(width: 38, height: 38)
                                Image(systemName: loan.type.iconSystemName)
                                    .foregroundStyle(Color.accentColor)
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(loan.label.isEmpty ? loan.type.label : loan.label)
                                    .font(.callout.weight(.medium)).lineLimit(1)
                                ProgressView(value: calc.progressFraction).tint(.green).scaleEffect(y: 0.7)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(Decimal(calc.currentBalance).formatted(asCurrency: loan.currency))
                                    .font(.callout.weight(.semibold)).foregroundStyle(.red)
                                Text("\(calc.paymentsRemaining) \(lang["loan.paymentsRemaining"])")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal).padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    if idx < min(activeLoans.count, 3) - 1 { Divider().padding(.leading, 62) }
                }
            }
            .background(Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var creditLineWidget: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(lang["dashboard.myCreditLines"])
                    .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                NavigationLink(lang["action.seeAll"]) { CreditLinesView() }.font(.caption)
            }
            .padding(.horizontal)
            VStack(spacing: 0) {
                ForEach(Array(activeCreditLines.prefix(3).enumerated()), id: \.element.id) { idx, cl in
                    NavigationLink { CreditLineDetailView(creditLine: cl) } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle().stroke(Color(.tertiarySystemBackground), lineWidth: 3)
                                    .frame(width: 38, height: 38)
                                Circle()
                                    .trim(from: 0, to: CGFloat(cl.utilisationFraction))
                                    .stroke(cl.utilisationFraction >= 0.9 ? Color.red
                                            : cl.utilisationFraction >= 0.7 ? Color.orange
                                            : Color.green,
                                            style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                    .frame(width: 38, height: 38)
                                    .rotationEffect(.degrees(-90))
                                Image(systemName: "creditcard.fill")
                                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(cl.name).font(.callout.weight(.medium)).lineLimit(1)
                                Text(String(format: "%.2f%% / an",
                                            (cl.annualInterestRate as NSDecimalNumber).doubleValue))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(cl.currentBalance.formatted(asCurrency: cl.currency))
                                    .font(.callout.weight(.semibold)).foregroundStyle(.red)
                                Text("/ \(cl.creditLimit.formatted(asCurrency: cl.currency))")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal).padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    if idx < min(activeCreditLines.count, 3) - 1 { Divider().padding(.leading, 62) }
                }
            }
            .background(Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var upcomingWidget: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(lang["dashboard.upcoming"])
                    .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                NavigationLink(lang["action.seeAll"]) { RecurrencesView() }.font(.caption)
            }
            .padding(.horizontal)
            VStack(spacing: 0) {
                ForEach(Array(upcomingRecurrences.enumerated()), id: \.element.id) { idx, rule in
                    upcomingRow(rule).padding(.horizontal).padding(.vertical, 10)
                    if idx < upcomingRecurrences.count - 1 { Divider().padding(.leading, 68) }
                }
            }
            .background(Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
        }
    }

    private func upcomingRow(_ rule: RecurringTransaction) -> some View {
        let iconColor: Color = rule.category.flatMap { Color(hex: $0.colorHex) }
            ?? (rule.type == .income ? .green : .secondary)
        let iconName = rule.category?.iconSystemName
            ?? (rule.type == .income ? "arrow.down.circle" : "arrow.up.circle")
        let code = rule.account?.currency ?? Currencies.default
        let amtText = (rule.type == .income ? "+" : "−") + rule.amount.formatted(asCurrency: code)
        let dueColor: Color = { switch rule.dueDateColor {
            case .overdue: return .red; case .soon: return .orange; case .normal: return .secondary
        }}()
        return HStack(spacing: 12) {
            ZStack {
                Circle().fill(iconColor.opacity(0.15)).frame(width: 40, height: 40)
                Image(systemName: iconName).foregroundStyle(iconColor)
                    .font(.system(size: 17, weight: .semibold))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.displayTitle).font(.body.weight(.medium)).lineLimit(1)
                Text(rule.frequency.shortLabel).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(amtText).font(.body.weight(.semibold))
                    .foregroundStyle(rule.type == .income ? .green : .primary)
                Text(rule.dueDateLabel).font(.caption2).foregroundStyle(dueColor)
            }
        }
    }

    private var recentWidget: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(lang["dashboard.recentTx"])
                    .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                NavigationLink(lang["action.seeAll"]) { TransactionsView() }.font(.caption)
            }
            .padding(.horizontal)
            if recentTransactions.isEmpty {
                Text(lang["dashboard.noTx"])
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity).padding(.vertical, 24)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recentTransactions.enumerated()), id: \.element.id) { idx, tx in
                        NavigationLink { AddEditTransactionView(mode: .edit(tx)) } label: {
                            TransactionRow(transaction: tx)
                                .padding(.horizontal).padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        if idx < recentTransactions.count - 1 { Divider().padding(.leading, 68) }
                    }
                }
                .background(Color(.secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
            }
        }
    }

    // MARK: Budgets widget (standalone, separate from BudgetDashboardSection)

    @ViewBuilder
    private func budgetSectionWidget(currency: String) -> some View {
        // Delegate to BudgetDashboardSection's budget-only card
        // by wrapping it in a minimal view that only shows the budget block
        BudgetOnlyDashboardCard(currency: currency)
    }

    // MARK: Savings widget

    @ViewBuilder
    private func savingsWidget(currency: String) -> some View {
        SavingsOnlyDashboardCard(currency: currency)
    }
}

// MARK: - Thin wrapper views for isolated budget / savings display

private struct BudgetOnlyDashboardCard: View {
    @Environment(LanguageManager.self) private var lang
    @Query(filter: #Predicate<Budget> { $0.isActive }, sort: \Budget.createdAt)
    private var activeBudgets: [Budget]
    @Query(sort: \Transaction.date, order: .reverse) private var allTransactions: [Transaction]
    let currency: String

    var body: some View {
        let statuses = activeBudgets
            .filter { $0.currency == currency }
            .map { BudgetStatus(budget: $0, spent: BudgetCalculator.spent(for: $0, in: allTransactions)) }
            .sorted { $0.fraction > $1.fraction }
            .prefix(3).map { $0 }
        if !statuses.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(lang["budget.title"])
                        .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                    Spacer()
                    NavigationLink(lang["action.seeAll"]) { BudgetsView() }.font(.caption)
                }
                .padding(.horizontal)
                BudgetCard(statuses: statuses)
            }
        }
    }
}

private struct SavingsOnlyDashboardCard: View {
    @Environment(LanguageManager.self) private var lang
    @Query(filter: #Predicate<SavingsProject> { $0.isActive },
           sort: \SavingsProject.createdAt) private var projects: [SavingsProject]
    let currency: String

    var body: some View {
        let filtered = projects.filter { $0.currency == currency }
        if !filtered.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(lang["savings.title"])
                        .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                    Spacer()
                    NavigationLink(lang["action.seeAll"]) { SavingsProjectsView() }.font(.caption)
                }
                .padding(.horizontal)
                SavingsGoalsCard(projects: filtered, currency: currency)
            }
        }
    }
}
