//
//  TransactionsView.swift
//  FinTrack
//

import SwiftUI
import SwiftData

struct TransactionsView: View {
    @Environment(\.modelContext) private var context
    @Environment(LanguageManager.self) private var lang

    @Query(sort: \Transaction.date, order: .reverse)
    private var allTransactions: [Transaction]

    @Query(filter: #Predicate<Account> { !$0.isArchived },
           sort: \Account.createdAt, order: .forward)
    private var accounts: [Account]

    @Query(filter: #Predicate<Transaction> { $0.needsReview },
           sort: \Transaction.date, order: .reverse)
    private var reviewTransactions: [Transaction]

    @Query(filter: #Predicate<RecurringTransaction> { $0.isActive },
           sort: \RecurringTransaction.nextDueDate, order: .forward)
    private var activeRecurring: [RecurringTransaction]

    @State private var filterType: TypeFilter = .all
    @State private var filterAccount: Account? = nil
    @State private var searchText: String = ""
    @State private var debouncedSearch: String = ""
    @State private var debounceTask: Task<Void, Error>? = nil
    @State private var viewMode: ViewMode = .list
    @State private var showAddTransaction = false
    @State private var editingTransaction: Transaction?
    @State private var showReview = false

    enum ViewMode { case list, calendar }
    @State private var showAddTransfer = false
    @State private var showImportStatement = false

    enum TypeFilter: String, CaseIterable, Identifiable {
        case all, income, expense
        var id: String { rawValue }
        func label(using lang: LanguageManager) -> String {
            switch self {
            case .all:     return lang["label.all"]
            case .income:  return lang["label.incomes"]
            case .expense: return lang["label.expenses"]
            }
        }
    }

    enum FutureHorizon: String, CaseIterable, Identifiable {
        case none, month1, month3, year1
        var id: String { rawValue }
        func label(using lang: LanguageManager) -> String {
            switch self {
            case .none:   return lang["tx.upcoming.none"]
            case .month1: return lang["tx.upcoming.1m"]
            case .month3: return lang["tx.upcoming.3m"]
            case .year1:  return lang["tx.upcoming.1y"]
            }
        }
        var endDate: Date? {
            let cal = Calendar.current
            switch self {
            case .none:   return nil
            case .month1: return cal.date(byAdding: .month, value: 1, to: .now)
            case .month3: return cal.date(byAdding: .month, value: 3, to: .now)
            case .year1:  return cal.date(byAdding: .year, value: 1, to: .now)
            }
        }
    }
    @State private var futureHorizon: FutureHorizon = .month1

    private var filteredTransactions: [Transaction] {
        allTransactions.filter { tx in
            // Type
            switch filterType {
            case .all: break
            case .income:  if tx.type != .income  { return false }
            case .expense: if tx.type != .expense { return false }
            }
            // Account
            if let acc = filterAccount, tx.account?.id != acc.id { return false }
            // Search
            let q = debouncedSearch.trimmingCharacters(in: .whitespaces).lowercased()
            if !q.isEmpty {
                let haystack = [
                    tx.payee ?? "",
                    tx.note,
                    tx.category?.name ?? "",
                    tx.account?.name ?? ""
                ].joined(separator: " ").lowercased()
                if !haystack.contains(q) { return false }
            }
            return true
        }
    }

    /// Group by date (day) for sectioned display.
    private var groupedTransactions: [(date: Date, items: [Transaction])] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: filteredTransactions) { tx in
            cal.startOfDay(for: tx.date)
        }
        return grouped
            .map { (date: $0.key, items: $0.value) }
            .sorted { $0.date > $1.date }
    }

    private struct UpcomingItem: Identifiable {
        let id: String
        let rule: RecurringTransaction
        let date: Date
    }

    /// Projected future recurring occurrences within the selected horizon.
    private var upcomingItems: [UpcomingItem] {
        guard let horizonEnd = futureHorizon.endDate else { return [] }
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        var items: [UpcomingItem] = []
        for rule in activeRecurring {
            switch filterType {
            case .all: break
            case .income:  if rule.type != .income  || rule.isTransfer { continue }
            case .expense: if rule.type != .expense || rule.isTransfer { continue }
            }
            if let acc = filterAccount, rule.account?.id != acc.id { continue }
            var d = rule.nextDueDate
            var guardCount = 0
            while d <= horizonEnd && guardCount < 500 {
                if let end = rule.endDate, d > end { break }
                if d > today {
                    items.append(UpcomingItem(
                        id: "\(rule.persistentModelID.hashValue)-\(Int(d.timeIntervalSince1970))",
                        rule: rule, date: d))
                }
                d = rule.frequency.nextDate(after: d)
                guardCount += 1
            }
        }
        return items.sorted { $0.date < $1.date }
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewMode == .calendar {
                    TransactionsCalendarView(
                        realTransactions: allTransactions,
                        typeFilter: filterType,
                        accountFilter: filterAccount
                    )
                } else if allTransactions.isEmpty {
                    ContentUnavailableView(
                        lang["tx.noTx"],
                        systemImage: "list.bullet.rectangle",
                        description: Text(lang["tx.noTx.sub"])
                    )
                } else {
                    list
                }
            }
            .navigationTitle(lang["tx.title"])
            .searchable(text: $searchText, prompt: lang["action.search"])
            .onChange(of: searchText) { _, new in
                debounceTask?.cancel()
                debounceTask = Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    debouncedSearch = new
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    filterMenu
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        withAnimation { viewMode = viewMode == .list ? .calendar : .list }
                    } label: {
                        Image(systemName: viewMode == .list ? "calendar" : "list.bullet")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showAddTransaction = true
                        } label: {
                            Label(lang["tx.create"], systemImage: "plus")
                        }
                        Button {
                            showAddTransfer = true
                        } label: {
                            Label(lang["transfer.create"], systemImage: "arrow.left.arrow.right")
                        }
                        Divider()
                        Button {
                            showImportStatement = true
                        } label: {
                            Label(lang["import.ofx.title"], systemImage: "arrow.down.doc")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill").font(.title3)
                    }
                    .disabled(accounts.isEmpty)
                }
            }
            .sheet(isPresented: $showAddTransaction) {
                NavigationStack {
                    AddEditTransactionView(mode: .create)
                }
            }
            .sheet(isPresented: $showImportStatement) {
                NavigationStack {
                    ProGated(feature: .fileImport) {
                        OFXImportView()
                    }
                }
            }
            .sheet(isPresented: $showAddTransfer) {
                AddTransferView()
            }
            .sheet(isPresented: $showReview) {
                DuplicateReviewView()
            }
            .sheet(item: $editingTransaction) { tx in
                NavigationStack {
                    AddEditTransactionView(mode: .edit(tx))
                }
            }
        }
    }

    private var list: some View {
        List {
            if !reviewTransactions.isEmpty {
                Section {
                    Button { showReview = true } label: { reviewBanner }
                        .buttonStyle(.plain)
                }
                .listRowBackground(Color.orange.opacity(0.08))
            }
            if futureHorizon != .none {
                Section(header: Text(lang["tx.upcoming.title"])) {
                    if upcomingItems.isEmpty {
                        Text(lang["tx.upcoming.empty"])
                            .font(.callout).foregroundStyle(.secondary)
                    } else {
                        ForEach(upcomingItems) { item in
                            upcomingRow(item)
                        }
                    }
                }
            }
            ForEach(groupedTransactions, id: \.date) { group in
                Section(header: Text(headerLabel(for: group.date))) {
                    ForEach(group.items) { tx in
                        Button {
                            editingTransaction = tx
                        } label: {
                            TransactionRow(transaction: tx)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            if tx.externalId == nil {
                                Button { TransactionStatusManager.toggleSkip(tx, context: context) } label: {
                                    Label(tx.status == .skipped ? lang["action.unskip"] : lang["action.skip"],
                                          systemImage: tx.status == .skipped ? "arrow.uturn.backward" : "minus.circle")
                                }
                                .tint(.orange)
                                Button { TransactionStatusManager.toggleReconciled(tx, context: context) } label: {
                                    Label(tx.status == .reconciled ? lang["action.unreconcile"] : lang["action.reconcile"],
                                          systemImage: "checkmark.seal")
                                }
                                .tint(.green)
                            }
                        }
                    }
                    .onDelete { offsets in
                        delete(in: group.items, at: offsets)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if filteredTransactions.isEmpty && !allTransactions.isEmpty {
                ContentUnavailableView.search
            }
        }
    }

    private var reviewBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(lang["review.banner.title"])
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("\(reviewTransactions.count) \(lang["review.banner.sub"])")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
    }

    private var filterMenu: some View {
        Menu {
            Picker("Type", selection: $filterType) {
                ForEach(TypeFilter.allCases) { f in
                    Text(f.label(using: lang)).tag(f)
                }
            }
            Divider()
            Picker(lang["label.account"], selection: $filterAccount) {
                Text(lang["tx.allAccounts"]).tag(Account?.none)
                ForEach(accounts) { a in
                    Text(a.name).tag(Optional(a))
                }
            }
            Divider()
            Picker(lang["tx.upcoming.show"], selection: $futureHorizon) {
                ForEach(FutureHorizon.allCases) { h in
                    Text(h.label(using: lang)).tag(h)
                }
            }
        } label: {
            Image(systemName: hasActiveFilters
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease.circle")
        }
    }

    private var hasActiveFilters: Bool {
        filterType != .all || filterAccount != nil || futureHorizon != .none
    }

    private func headerLabel(for date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return lang["label.today"] }
        if cal.isDateInYesterday(date) { return lang["label.yesterday"] }
        let formatted = FormatterCache.datePattern("EEEE d MMMM yyyy",
                                                       locale: LanguageManager.shared.locale).string(from: date)
        return formatted.capitalized
    }

    private func delete(in items: [Transaction], at offsets: IndexSet) {
        var affected: Set<Account.ID> = []
        for index in offsets {
            if let a = items[index].account { affected.insert(a.id) }
            context.delete(items[index])
        }
        // Recalculate after deletes
        for acc in accounts where affected.contains(acc.id) {
            acc.recalculateBalance()
        }
        try? context.save()
    }

    @ViewBuilder
    private func upcomingRow(_ item: UpcomingItem) -> some View {
        let rule = item.rule
        let iconColor: Color = rule.category.map { Color(hex: $0.colorHex) } ?? .secondary
        let code = rule.account?.currency ?? Currencies.default
        let amountStr = rule.isTransfer
            ? rule.amount.formatted(asCurrency: code)
            : (rule.type == .income ? "+" : "−") + rule.amount.formatted(asCurrency: code)
        let amountColor: Color = rule.isTransfer ? .secondary : (rule.type == .income ? .green : .primary)
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(iconColor.opacity(0.12)).frame(width: 36, height: 36)
                Image(systemName: rule.isTransfer
                      ? "arrow.left.arrow.right"
                      : (rule.category?.iconSystemName ?? "clock.arrow.circlepath"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(iconColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.displayTitle).font(.body.weight(.medium)).lineLimit(1)
                Text(item.date.appFormatted()).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(amountStr).font(.body.weight(.medium)).foregroundStyle(amountColor)
        }
        .opacity(0.7)
    }
}

#Preview {
    TransactionsView()
        .modelContainer(for: [Account.self, Transaction.self, Category.self], inMemory: true)
}
