//
//  DashboardView.swift
//  FinTrack
//
//  Driven by DashboardConfigManager — widgets are shown in the user's
//  chosen order and can be hidden / reordered from DashboardLibraryView.
//

import SwiftUI
import SwiftData

/// Résumé mensuel multidevise pour le widget « Ce mois-ci ».
/// Les totaux sont convertis dans la devise d'affichage ; `byCurrency`
/// conserve les montants natifs pour la ventilation.
private struct MonthSummary {
    let convertedIncome: Decimal
    let convertedExpense: Decimal
    let displayCurrency: String
    let hasConversion: Bool
    let byCurrency: [(currency: String, income: Decimal, expense: Decimal)]
}

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

    /// Transactions du mois courant — filtre SQL sur la date (voir init()).
    /// Alimente le widget « Ce mois-ci » et se met à jour automatiquement.
    @Query private var monthTransactions: [Transaction]

    @Query private var recentTransactions: [Transaction]

    /// One-off transactions dated tomorrow or later (manual scheduled + transfer legs).
    /// Drives the "next 7 days" widget alongside projected recurring occurrences.
    @Query private var futureTransactions: [Transaction]

    @Query(filter: #Predicate<CreditLine> { $0.isActive },
           sort: [SortDescriptor(\CreditLine.sortIndex, order: .forward),
                  SortDescriptor(\CreditLine.createdAt, order: .forward)])
    private var activeCreditLines: [CreditLine]

    @Query(filter: #Predicate<Loan> { $0.isActive },
           sort: [SortDescriptor(\Loan.sortIndex, order: .forward),
                  SortDescriptor(\Loan.createdAt, order: .forward)])
    private var activeLoans: [Loan]

    @Query(filter: #Predicate<RecurringTransaction> { $0.isActive },
           sort: \RecurringTransaction.nextDueDate, order: .forward)
    private var activeRecurring: [RecurringTransaction]

    // Future one-time transfer transactions (expense leg, next 60 days)
    @Query(filter: #Predicate<Transaction> { $0.transferPairId != nil && $0.typeRaw == "expense" },
           sort: \Transaction.date, order: .forward)
    private var futureTransferExpenses: [Transaction]

    @Query(filter: #Predicate<AppNotification> { !$0.isRead })
    private var unreadNotifications: [AppNotification]

    @State private var config           = DashboardConfigManager.shared
    @State private var showAddTransaction = false
    @State private var showScanReceipt    = false
    @State private var showNotifications  = false
    @State private var pendingRecurringDeepLink = false
    @State private var showAddAccount     = false
    @State private var showAddTransfer    = false
    @State private var showLibrary        = false
    @State private var editingTransaction: Transaction?

    // MARK: - Init (performance: limited @Query for recent transactions)

    init() {
        // « Récent » = passé/présent uniquement : on exclut les transactions datées
        // dans le futur (planifiées) pour qu'elles ne remontent pas en tête de liste.
        let startOfTomorrow = Calendar.current.startOfDay(
            for: Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
        )
        var desc = FetchDescriptor<Transaction>(
            predicate: #Predicate<Transaction> { $0.date < startOfTomorrow },
            sortBy: [SortDescriptor(\Transaction.date, order: .reverse)]
        )
        desc.fetchLimit = 10
        _recentTransactions = Query(desc)

        // Mois courant : filtrage en SQL plutôt qu'en mémoire sur toutes les transactions.
        let monthStart = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
        _monthTransactions = Query(
            filter: #Predicate<Transaction> { $0.date >= monthStart },
            sort: \Transaction.date, order: .reverse
        )

        // À venir : transactions ponctuelles datées demain ou après (one-off + virements).
        _futureTransactions = Query(
            filter: #Predicate<Transaction> { $0.date >= startOfTomorrow },
            sort: \Transaction.date, order: .forward
        )
    }

    // MARK: - Derived data

    private var totalsByCurrency: [(currency: String, total: Decimal)] {
        Dictionary(grouping: accounts, by: \.currency)
            .map { (currency: $0.key, total: $0.value.reduce(Decimal(0)) { $0 + $1.balance }) }
            .sorted { $0.currency < $1.currency }
    }

    // recentTransactions fed by a dedicated limited @Query (C2 perf fix)
    // See init() below for fetchLimit: 10
    private var recurringTransfers: [RecurringTransaction] {
        let horizon = Calendar.current.date(byAdding: .day, value: 60, to: .now) ?? .now
        return activeRecurring.filter { $0.isTransfer && $0.nextDueDate <= horizon }
    }

    private var upcomingTransferTx: [Transaction] {
        let now     = Date()
        let horizon = Calendar.current.date(byAdding: .day, value: 60, to: now) ?? now
        return futureTransferExpenses.filter { $0.date > now && $0.date <= horizon }
    }

    private struct UpcomingItem: Identifiable {
        let id: String
        let date: Date
        let title: String
        let amount: Decimal        // valeur absolue
        let currency: String
        let isIncome: Bool
        let isTransfer: Bool
        let iconName: String       // SF Symbol (catégorie ou défaut ; transfert géré au rendu)
        let colorHex: String?      // couleur de catégorie ; nil → secondaire
    }

    /// Échéances des 7 prochains jours, toutes sources confondues, triées par date
    /// (symétrique de « Récent ») :
    ///  1) récurrences (revenus, dépenses, virements) — hors paiements de prêt ;
    ///  2) transactions ponctuelles déjà planifiées (one-off et virements) ;
    ///  3) prochain paiement de chaque prêt, depuis son échéancier d'amortissement ;
    ///  4) paiement minimum des marges sans remboursement récurrent configuré.
    private var upcomingItems: [UpcomingItem] {
        let cal = Calendar.current
        let startOfTomorrow = cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: .now) ?? .now)
        let horizonEnd = cal.date(byAdding: .day, value: 7, to: startOfTomorrow) ?? startOfTomorrow
        var items: [UpcomingItem] = []

        // 1) Projections des règles récurrentes (occurrences non matérialisées).
        for rule in activeRecurring {
            // Les paiements de prêt sont projetés depuis l'échéancier d'amortissement (plus bas),
            // donc on les exclut ici pour éviter le double comptage. Les règles de marge
            // (remboursement configuré) restent projetées normalement ; le paiement minimum
            // n'est ajouté que pour les marges sans remboursement configuré (source 4).
            if rule.isLoanPayment { continue }
            var d = rule.nextDueDate
            var guardCount = 0
            while d < horizonEnd && guardCount < 100 {
                if let end = rule.endDate, d > end { break }
                if d >= startOfTomorrow {
                    items.append(UpcomingItem(
                        id: "r-\(rule.persistentModelID.hashValue)-\(Int(d.timeIntervalSince1970))",
                        date: d,
                        title: rule.displayTitle,
                        amount: rule.amount,
                        currency: rule.account?.currency ?? Currencies.default,
                        isIncome: rule.type == .income,
                        isTransfer: rule.isTransfer,
                        iconName: rule.category?.iconSystemName
                            ?? (rule.type == .income ? "arrow.down.circle" : "arrow.up.circle"),
                        colorHex: rule.category?.colorHex))
                }
                d = rule.frequency.nextDate(after: d)
                guardCount += 1
            }
        }

        // 2) Transactions ponctuelles déjà planifiées (une seule jambe par virement).
        for tx in futureTransactions where tx.date >= startOfTomorrow && tx.date < horizonEnd {
            if tx.transferPairId != nil && tx.type != .expense { continue }
            let title: String = {
                if tx.transferPairId != nil {
                    if let p = tx.payee, !p.isEmpty { return p }
                    return lang["transfer.title"]
                }
                if let p = tx.payee, !p.isEmpty { return p }
                if let cat = tx.category { return cat.localizedName }
                return tx.type == .income ? lang["tx.type.income"] : lang["tx.type.expense"]
            }()
            items.append(UpcomingItem(
                id: "t-\(tx.persistentModelID.hashValue)",
                date: tx.date,
                title: title,
                amount: tx.amount,
                currency: tx.account?.currency ?? Currencies.default,
                isIncome: tx.type == .income,
                isTransfer: tx.transferPairId != nil,
                iconName: tx.category?.iconSystemName
                    ?? (tx.type == .income ? "arrow.down.circle" : "arrow.up.circle"),
                colorHex: tx.category?.colorHex))
        }

        // 3) Prochain paiement de chaque prêt actif, depuis l'échéancier d'amortissement
        //    (source de vérité), indépendamment de la règle de paiement éventuelle.
        for loan in activeLoans {
            let calc = loan.calculator
            let nextK = calc.paymentsElapsedToday + 1
            guard nextK <= calc.effectivePayments else { continue }   // prêt soldé
            let d = calc.paymentDate(nextK)
            guard d >= startOfTomorrow && d < horizonEnd else { continue }
            items.append(UpcomingItem(
                id: "loan-\(loan.persistentModelID.hashValue)-\(Int(d.timeIntervalSince1970))",
                date: d,
                title: loan.label.isEmpty ? loan.type.label : loan.label,
                amount: Decimal(calc.paymentAmount),
                currency: loan.currency,
                isIncome: false,
                isTransfer: false,
                iconName: "building.columns.fill",
                colorHex: "#5856D6"))
        }

        // 4) Paiement minimum à la date de relevé, uniquement pour les marges SANS
        //    remboursement récurrent configuré (sinon c'est la règle, source 1, qui
        //    s'affiche) et avec un solde dû.
        for line in activeCreditLines where line.currentBalance > 0 && line.paymentRule == nil {
            var comps = cal.dateComponents([.year, .month], from: startOfTomorrow)
            comps.day = min(max(line.statementDay, 1), 28)
            var d = cal.date(from: comps) ?? startOfTomorrow
            if d < startOfTomorrow { d = cal.date(byAdding: .month, value: 1, to: d) ?? d }
            guard d < horizonEnd else { continue }
            items.append(UpcomingItem(
                id: "cl-\(line.persistentModelID.hashValue)-\(Int(d.timeIntervalSince1970))",
                date: d,
                title: line.name,
                amount: line.estimatedMinimumPayment,
                currency: line.currency,
                isIncome: false,
                isTransfer: false,
                iconName: "creditcard.fill",
                colorHex: "#FF9500"))
        }

        return items.sorted { $0.date < $1.date }
    }

    /// Liste plafonnée pour le widget du dashboard (la liste complète est dans l'écran Transactions).
    private var upcomingItemsLimited: [UpcomingItem] { Array(upcomingItems.prefix(10)) }

    private var thisMonthSummary: MonthSummary {
        let display = rates.displayCurrency
        // Exclut les virements (transferPairId) et les statuts qui ne comptent
        // pas dans le solde (scheduled, skipped) — cohérent avec Account.balance.
        let relevant = monthTransactions.filter {
            $0.transferPairId == nil && $0.status.countsTowardBalance
        }
        let grouped = Dictionary(grouping: relevant) { $0.account?.currency ?? display }
        let rows = grouped.map { (cur, txs) -> (currency: String, income: Decimal, expense: Decimal) in
            let inc = txs.filter { $0.type == .income  }.reduce(Decimal(0)) { $0 + $1.amount }
            let exp = txs.filter { $0.type == .expense }.reduce(Decimal(0)) { $0 + $1.amount }
            return (currency: cur, income: inc, expense: exp)
        }.sorted { $0.currency < $1.currency }

        let income  = rows.reduce(Decimal(0)) { $0 + rates.convert($1.income,  from: $1.currency, to: display) }
        let expense = rows.reduce(Decimal(0)) { $0 + rates.convert($1.expense, from: $1.currency, to: display) }
        let hasConversion = rows.contains { $0.currency != display }
        return MonthSummary(convertedIncome: income, convertedExpense: expense,
                            displayCurrency: display, hasConversion: hasConversion,
                            byCurrency: rows)
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
                else {
                    populated
                        .coachMarks(tour: "dashboard", steps: [
                            CoachStep(anchor: "dashboard.balance",
                                      title: lang["coach.dash.balance.title"],
                                      message: lang["coach.dash.balance.msg"]),
                            CoachStep(anchor: "dashboard.accounts",
                                      title: lang["coach.dash.accounts.title"],
                                      message: lang["coach.dash.accounts.msg"]),
                        ])
                }
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
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showNotifications = true
                    } label: {
                        Image(systemName: unreadNotifications.isEmpty ? "bell" : "bell.badge.fill")
                            .symbolRenderingMode(.multicolor)
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
                        if entitlements.hasPaidTier {
                            Button { showScanReceipt = true } label: {
                                Label(lang["scan.title"], systemImage: "doc.text.viewfinder")
                            }
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
            .sheet(isPresented: $showNotifications, onDismiss: {
                // Fire the deep link only after the bell has fully closed, so the
                // tab switch + navigation to Recurring aren't swallowed by the sheet.
                if pendingRecurringDeepLink {
                    pendingRecurringDeepLink = false
                    NotificationCenter.default.post(name: .fintrackDeepLink, object: nil,
                                                    userInfo: ["tab": 3, "section": "recurring"])
                }
            }) {
                NotificationsView(onNavigateToRecurrences: { pendingRecurringDeepLink = true })
            }
            .sheet(isPresented: $showScanReceipt) { ScanReceiptView() }
            .sheet(isPresented: $showAddTransfer) { AddTransferView() }
            .sheet(isPresented: $showAddAccount)   { AddEditAccountView(mode: .create) }
            .sheet(isPresented: $showLibrary)      { DashboardLibraryView() }
            .sheet(item: $editingTransaction) { tx in
                NavigationStack { AddEditTransactionView(mode: .edit(tx)) }
            }
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

    /// Collapsed render list — the three analytics widget IDs (.balanceProjection,
    /// .incomeVsExpenses, .categoryBreakdown) all map to a single AnalyticsDashboardSection.
    /// Only the first analytics ID found in the enabled list triggers a render;
    /// the others are skipped here but still passed via analyticsWidgets so all
    /// enabled sub-charts appear within the single section.
    private var renderOrder: [DashboardWidgetID] {
        let analyticsIDs: Set<DashboardWidgetID> = [.balanceProjection, .incomeVsExpenses, .categoryBreakdown]
        var seenAnalytics = false
        return config.enabled.filter { id in
            guard analyticsIDs.contains(id) else { return true }
            if seenAnalytics { return false }
            seenAnalytics = true
            return true
        }
    }

    private var populated: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(renderOrder) { widgetId in
                    widgetView(for: widgetId)
                }
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Widget dispatcher

    @ViewBuilder
    private func widgetView(for id: DashboardWidgetID) -> some View {
        if id.requiresPro && !entitlements.hasPaidTier {
            // Pro-only widget — show upsell teaser for Courant users
            proTeaser(for: id)
        } else {
            switch id {
            case .globalBalance:
                globalBalanceWidget.coachAnchor("dashboard.balance")

            case .accountsCarousel:
                accountsCarouselWidget.coachAnchor("dashboard.accounts")

            case .monthSummary:
                if !accounts.isEmpty { monthSummaryWidget }

            case .loans:
                if !activeLoans.isEmpty { loanWidget }

            case .creditLines:
                if !activeCreditLines.isEmpty { creditLineWidget }

            case .cashFlow:
                if !accounts.isEmpty {
                    BudgetDashboardSection(
                        monthTransactions: monthTransactions,
                        recurring: activeRecurring,
                        accounts: accounts,
                        displayCurrency: rates.displayCurrency
                    )
                    .id("cashFlow")
                }

            case .budgets:
                budgetSectionWidget()

            case .savingsGoals:
                savingsWidget()

            case .balanceProjection, .incomeVsExpenses, .categoryBreakdown:
                if !accounts.isEmpty {
                    AnalyticsDashboardSection(
                        accounts: accounts,
                        transactions: allTransactions,
                        activeRecurring: activeRecurring,
                        visibleWidgets: analyticsWidgets
                    )
                    .id("analytics")
                }

            case .upcomingRecurring:
                if !upcomingItems.isEmpty { upcomingWidget }

            case .recentTransactions:
                recentWidget

            case .netWorth:
                NetWorthWidget(
                    accounts: accounts,
                    loans: activeLoans,
                    creditLines: activeCreditLines
                )

            case .exchangeRates:
                ExchangeRateWidget()

            case .upcomingTransfers:
                UpcomingTransfersWidget(
                    recurringTransfers: recurringTransfers,
                    futureTransferTx: upcomingTransferTx
                )

            case .registeredRoom:
                RegisteredRoomWidget()
            }
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
                Text(id.title)
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
                        Text(Currencies.info(for: row.currency).name)
                            .font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(row.total.formatted(asCurrency: row.currency))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(row.total >= 0 ? Color.primary : Color.red)
                            if row.currency != rates.displayCurrency,
                               rates.showConvertedAmounts,
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
        VStack(alignment: .leading, spacing: 8) {
            Text(lang["dashboard.thisMonth"] + " (\(summary.displayCurrency))")
                .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                .padding(.horizontal)

            // Totaux convertis dans la devise d'affichage
            HStack(spacing: 12) {
                summaryTile(lang["label.incomes"],  value: summary.convertedIncome,
                            currency: summary.displayCurrency, approx: summary.hasConversion,
                            color: .green, icon: "arrow.down.left.circle.fill")
                summaryTile(lang["label.expenses"], value: summary.convertedExpense,
                            currency: summary.displayCurrency, approx: summary.hasConversion,
                            color: .red, icon: "arrow.up.right.circle.fill")
            }
            .padding(.horizontal)

            // Ventilation par devise (montants natifs) — si plusieurs devises ou conversion
            if summary.byCurrency.count > 1 || summary.hasConversion {
                VStack(spacing: 8) {
                    ForEach(summary.byCurrency, id: \.currency) { row in
                        HStack {
                            Text(Currencies.info(for: row.currency).name)
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text("+ " + row.income.formatted(asCurrency: row.currency))
                                .font(.caption.weight(.medium)).foregroundStyle(.green)
                            Text("− " + row.expense.formatted(asCurrency: row.currency))
                                .font(.caption.weight(.medium)).foregroundStyle(.red)
                        }
                    }
                }
                .padding(12)
                .background(Color(.secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
            }
        }
    }

    private func summaryTile(_ title: String, value: Decimal, currency: String, approx: Bool,
                              color: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundStyle(color)
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Text((approx ? "≈ " : "") + value.formatted(asCurrency: currency))
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
                NavigationLink(lang["action.seeAll"]) { TransactionsView() }.font(.caption)
            }
            .padding(.horizontal)
            VStack(spacing: 0) {
                ForEach(Array(upcomingItemsLimited.enumerated()), id: \.element.id) { idx, item in
                    upcomingRow(item).padding(.horizontal).padding(.vertical, 10)
                    if idx < upcomingItemsLimited.count - 1 { Divider().padding(.leading, 68) }
                }
            }
            .background(Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
        }
    }

    private func upcomingRow(_ item: UpcomingItem) -> some View {
        let iconColor: Color = item.colorHex.map { Color(hex: $0) }
            ?? (item.isTransfer ? .blue : (item.isIncome ? .green : .secondary))
        let symbol = item.isTransfer ? "arrow.left.arrow.right" : item.iconName
        let amtText = item.isTransfer
            ? item.amount.formatted(asCurrency: item.currency)
            : (item.isIncome ? "+" : "−") + item.amount.formatted(asCurrency: item.currency)
        let amtColor: AnyShapeStyle = item.isTransfer
            ? AnyShapeStyle(.secondary)
            : (item.isIncome ? AnyShapeStyle(Color.green) : AnyShapeStyle(.primary))
        return HStack(spacing: 12) {
            ZStack {
                Circle().fill(iconColor.opacity(0.15)).frame(width: 40, height: 40)
                Image(systemName: symbol).foregroundStyle(iconColor)
                    .font(.system(size: 17, weight: .semibold))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.body.weight(.medium)).lineLimit(1)
                Text(item.date.appFormatted()).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(amtText).font(.body.weight(.semibold)).foregroundStyle(amtColor)
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
                        Button { editingTransaction = tx } label: {
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
    private func budgetSectionWidget() -> some View {
        BudgetOnlyDashboardCard()
    }

    // MARK: Savings widget

    @ViewBuilder
    private func savingsWidget() -> some View {
        SavingsOnlyDashboardCard()
    }
}

// MARK: - Thin wrapper views for isolated budget / savings display

private struct BudgetOnlyDashboardCard: View {
    @Environment(LanguageManager.self) private var lang
    @Query(filter: #Predicate<Budget> { $0.isActive },
           sort: [SortDescriptor(\Budget.sortIndex, order: .forward),
                  SortDescriptor(\Budget.createdAt, order: .forward)])
    private var activeBudgets: [Budget]
    @Query(sort: \Transaction.date, order: .reverse) private var allTransactions: [Transaction]

    var body: some View {
        // Tous les budgets actifs (toutes devises) dans l'ordre manuel ; max 3.
        let statuses = activeBudgets
            .prefix(3)
            .map { BudgetStatus(budget: $0, spent: BudgetCalculator.spent(for: $0, in: allTransactions)) }
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
           sort: [SortDescriptor(\SavingsProject.sortIndex, order: .forward),
                  SortDescriptor(\SavingsProject.createdAt, order: .forward)])
    private var projects: [SavingsProject]

    var body: some View {
        // Tous les projets actifs (toutes devises) dans l'ordre manuel ; max 3 (géré par la carte).
        if !projects.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(lang["savings.title"])
                        .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                    Spacer()
                    NavigationLink(lang["action.seeAll"]) { SavingsProjectsView() }.font(.caption)
                }
                .padding(.horizontal)
                SavingsGoalsCard(projects: projects)
            }
        }
    }
}
