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
                monthSummarySection
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
        .modelContainer(for: [Account.self, Transaction.self, Category.self], inMemory: true)
}
