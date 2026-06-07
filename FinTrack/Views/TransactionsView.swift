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

    @State private var filterType: TypeFilter = .all
    @State private var filterAccount: Account? = nil
    @State private var searchText: String = ""
    @State private var debouncedSearch: String = ""
    @State private var debounceTask: Task<Void, Error>? = nil
    @State private var showAddTransaction = false
    @State private var showAddTransfer = false

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

    var body: some View {
        NavigationStack {
            Group {
                if allTransactions.isEmpty {
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
            .sheet(isPresented: $showAddTransfer) {
                AddTransferView()
            }
        }
    }

    private var list: some View {
        List {
            ForEach(groupedTransactions, id: \.date) { group in
                Section(header: Text(headerLabel(for: group.date))) {
                    ForEach(group.items) { tx in
                        NavigationLink {
                            AddEditTransactionView(mode: .edit(tx))
                        } label: {
                            TransactionRow(transaction: tx)
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
        } label: {
            Image(systemName: hasActiveFilters
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease.circle")
        }
    }

    private var hasActiveFilters: Bool {
        filterType != .all || filterAccount != nil
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
        for index in offsets {
            context.delete(items[index])
        }
        try? context.save()
    }
}

#Preview {
    TransactionsView()
        .modelContainer(for: [Account.self, Transaction.self, Category.self], inMemory: true)
}
