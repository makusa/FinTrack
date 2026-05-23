//
//  DashboardView.swift
//  FinTrack
//

import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var context

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

    @State private var showAddTransaction = false
    @State private var showAddAccount = false

    // Group accounts by currency for the totals strip.
    private var totalsByCurrency: [(currency: String, total: Decimal)] {
        let grouped = Dictionary(grouping: accounts, by: \.currency)
        return grouped
            .map { (currency: $0.key, total: $0.value.reduce(Decimal(0)) { $0 + $1.balance }) }
            .sorted { $0.currency < $1.currency }
    }

    private var recentTransactions: [Transaction] {
        Array(allTransactions.prefix(10))
    }

    /// Recurring rules due within the next 30 days, capped at 5 for the dashboard.
    private var upcomingRecurrences: [RecurringTransaction] {
        let horizon = Calendar.current.date(byAdding: .day, value: 30, to: .now) ?? .now
        return Array(activeRecurring.filter { $0.nextDueDate <= horizon }.prefix(5))
    }

    private var thisMonthSummary: (income: Decimal, expense: Decimal, currency: String?) {
        let cal = Calendar.current
        let startOfMonth = cal.dateInterval(of: .month, for: .now)?.start ?? .now
        let monthTx = allTransactions.filter { $0.date >= startOfMonth }
        // For simplicity v1: only sum transactions sharing the most common currency
        // among accounts. Multi-currency aggregation requires FX rates we don't have yet.
        let dominantCurrency = mostCommonCurrency()
        let filtered = monthTx.filter { $0.account?.currency == dominantCurrency }
        let income = filtered
            .filter { $0.type == .income }
            .reduce(Decimal(0)) { $0 + $1.amount }
        let expense = filtered
            .filter { $0.type == .expense }
            .reduce(Decimal(0)) { $0 + $1.amount }
        return (income, expense, dominantCurrency)
    }

    private func mostCommonCurrency() -> String? {
        let counts = Dictionary(grouping: accounts, by: \.currency).mapValues(\.count)
        return counts.max(by: { $0.value < $1.value })?.key
    }

    var body: some View {
        NavigationStack {
            Group {
                if accounts.isEmpty {
                    emptyState
                } else {
                    populated
                }
            }
            .navigationTitle("Tableau de bord")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddTransaction = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                    .disabled(accounts.isEmpty)
                }
            }
            .sheet(isPresented: $showAddTransaction) {
                NavigationStack {
                    AddEditTransactionView(mode: .create)
                }
            }
            .sheet(isPresented: $showAddAccount) {
                AddEditAccountView(mode: .create)
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "building.columns")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Bienvenue dans FinTrack")
                .font(.title2.weight(.semibold))
            Text("Commencez par ajouter un compte bancaire,\nune carte ou un portefeuille liquide.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            Button {
                showAddAccount = true
            } label: {
                Label("Ajouter mon premier compte", systemImage: "plus")
                    .font(.body.weight(.semibold))
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

    // MARK: - Populated

    private var populated: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                totalsSection
                accountsCarousel
                loanSection
                creditLineSection
                monthSummarySection
                if let currency = mostCommonCurrency() {
                    BudgetDashboardSection(
                        recurring: activeRecurring,
                        loans: activeLoans,
                        currency: currency
                    )
                }
                if let currency = mostCommonCurrency() {
                    AnalyticsDashboardSection(
                        accounts: accounts,
                        transactions: allTransactions,
                        activeRecurring: activeRecurring,
                        currency: currency
                    )
                }
                upcomingSection
                recentSection
            }
            .padding(.vertical, 8)
        }
    }

    private var totalsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Solde global")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(totalsByCurrency, id: \.currency) { row in
                    HStack {
                        Text(Currencies.info(for: row.currency).nameFR)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(row.total.formatted(asCurrency: row.currency))
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(row.total >= 0 ? Color.primary : Color.red)
                    }
                }
            }
            .padding(16)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
        }
    }

    private var accountsCarousel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Mes comptes")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                NavigationLink("Tout voir") {
                    AccountsView()
                }
                .font(.caption)
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(accounts) { account in
                        NavigationLink {
                            AccountDetailView(account: account)
                        } label: {
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
    private var monthSummarySection: some View {
        let summary = thisMonthSummary
        if let currency = summary.currency {
            VStack(alignment: .leading, spacing: 8) {
                Text("Ce mois-ci (\(currency))")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                HStack(spacing: 12) {
                    summaryTile(
                        title: "Revenus",
                        value: summary.income,
                        currency: currency,
                        color: .green,
                        systemImage: "arrow.down.left.circle.fill"
                    )
                    summaryTile(
                        title: "Dépenses",
                        value: summary.expense,
                        currency: currency,
                        color: .red,
                        systemImage: "arrow.up.right.circle.fill"
                    )
                }
                .padding(.horizontal)
            }
        }
    }

    private func summaryTile(title: String, value: Decimal, currency: String,
                             color: Color, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(value.formatted(asCurrency: currency))
                .font(.headline.weight(.semibold))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var creditLineSection: some View {
        if !activeCreditLines.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Mes marges de crédit")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    NavigationLink("Tout voir") { CreditLinesView() }
                        .font(.caption)
                }
                .padding(.horizontal)

                VStack(spacing: 0) {
                    ForEach(Array(activeCreditLines.prefix(3).enumerated()), id: \.element.id) { idx, cl in
                        NavigationLink { CreditLineDetailView(creditLine: cl) } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .stroke(Color(.tertiarySystemBackground), lineWidth: 3)
                                        .frame(width: 38, height: 38)
                                    Circle()
                                        .trim(from: 0, to: CGFloat(cl.utilisationFraction))
                                        .stroke(cl.utilisationFraction >= 0.9 ? Color.red : cl.utilisationFraction >= 0.7 ? Color.orange : Color.green,
                                                style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                        .frame(width: 38, height: 38)
                                        .rotationEffect(.degrees(-90))
                                    Image(systemName: "creditcard.fill")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(cl.name)
                                        .font(.callout.weight(.medium)).lineLimit(1)
                                    Text(String(format: "%.2f%% / an", (cl.annualInterestRate as NSDecimalNumber).doubleValue))
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
                        if idx < min(activeCreditLines.count, 3) - 1 {
                            Divider().padding(.leading, 62)
                        }
                    }
                }
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
            }
        }
    }

    @ViewBuilder
    private var loanSection: some View {
        if !activeLoans.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Mes prêts")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    NavigationLink("Tout voir") { LoansView() }
                        .font(.caption)
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
                                    Text(loan.label.isEmpty ? loan.type.labelFR : loan.label)
                                        .font(.callout.weight(.medium)).lineLimit(1)
                                    ProgressView(value: calc.progressFraction)
                                        .tint(.green).scaleEffect(y: 0.7)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(Decimal(calc.currentBalance).formatted(asCurrency: loan.currency))
                                        .font(.callout.weight(.semibold)).foregroundStyle(.red)
                                    Text("\(calc.paymentsRemaining) versements")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal).padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        if idx < min(activeLoans.count, 3) - 1 {
                            Divider().padding(.leading, 62)
                        }
                    }
                }
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
            }
        }
    }

    @ViewBuilder
    private var upcomingSection: some View {
        if !upcomingRecurrences.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("À venir (30 jours)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    NavigationLink("Tout voir") {
                        RecurrencesView()
                    }
                    .font(.caption)
                }
                .padding(.horizontal)

                VStack(spacing: 0) {
                    ForEach(Array(upcomingRecurrences.enumerated()), id: \.element.id) { index, rule in
                        upcomingRow(rule)
                            .padding(.horizontal)
                            .padding(.vertical, 10)
                        if index < upcomingRecurrences.count - 1 {
                            Divider().padding(.leading, 68)
                        }
                    }
                }
                .background(Color(.secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
            }
        }
    }

    private func upcomingRow(_ rule: RecurringTransaction) -> some View {
        let iconColor: Color = {
            if let hex = rule.category?.colorHex { return Color(hex: hex) }
            return rule.type == .income ? .green : .secondary
        }()
        let iconName = rule.category?.iconSystemName
            ?? (rule.type == .income ? "arrow.down.circle" : "arrow.up.circle")
        let amountText: String = {
            let code = rule.account?.currency ?? Currencies.default
            return (rule.type == .income ? "+" : "−") + rule.amount.formatted(asCurrency: code)
        }()
        let dueLabelColor: Color = {
            switch rule.dueDateColor {
            case .overdue: return .red
            case .soon:    return .orange
            case .normal:  return .secondary
            }
        }()

        return HStack(spacing: 12) {
            ZStack {
                Circle().fill(iconColor.opacity(0.15)).frame(width: 40, height: 40)
                Image(systemName: iconName)
                    .foregroundStyle(iconColor)
                    .font(.system(size: 17, weight: .semibold))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.displayTitle)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(rule.frequency.shortLabelFR)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(amountText)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(rule.type == .income ? .green : .primary)
                Text(rule.dueDateLabel)
                    .font(.caption2)
                    .foregroundStyle(dueLabelColor)
            }
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Transactions récentes")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                NavigationLink("Tout voir") {
                    TransactionsView()
                }
                .font(.caption)
            }
            .padding(.horizontal)

            if recentTransactions.isEmpty {
                Text("Aucune transaction pour le moment.\nAppuyez sur + pour en ajouter une.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recentTransactions.enumerated()), id: \.element.id) { index, tx in
                        NavigationLink {
                            AddEditTransactionView(mode: .edit(tx))
                        } label: {
                            TransactionRow(transaction: tx)
                                .padding(.horizontal)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        if index < recentTransactions.count - 1 {
                            Divider().padding(.leading, 68)
                        }
                    }
                }
                .background(Color(.secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
            }
        }
    }
}

#Preview {
    DashboardView()
        .modelContainer(for: [Account.self, Transaction.self, Category.self, RecurringTransaction.self], inMemory: true)
}
