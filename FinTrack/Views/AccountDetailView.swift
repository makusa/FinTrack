//
//  AccountDetailView.swift
//  FinTrack
//

import SwiftUI
import SwiftData

struct AccountDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(LanguageManager.self) private var lang
    @Environment(\.dismiss) private var dismiss

    @Bindable var account: Account

    /// @Query-backed sorted transactions — avoids O(n log n) in-memory sort
    /// on every render by delegating sorting to SQLite.
    @Query private var sortedTransactions: [Transaction]

    init(account: Account) {
        self.account = account
        let id = account.persistentModelID
        _sortedTransactions = Query(
            filter: #Predicate<Transaction> { $0.account?.persistentModelID == id },
            sort: \Transaction.date, order: .reverse
        )
    }

    @State private var showEdit = false
    @State private var showAddTransaction = false
    @State private var showAddTransfer = false
    @State private var confirmArchive = false
    @State private var showRoomPlan = false
    @State private var showAddEntry = false

    @Query private var allPlans: [RegisteredRoomPlan]
    @Query private var allAccounts: [Account]

    var body: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    Group {
                        if account.iconSystemName.isEmpty, let domain = account.bankDomain {
                            BankLogoView(domain: domain, size: 52, cornerRadius: 12)
                                .frame(width: 72, height: 72)
                        } else {
                            let sfName = account.iconSystemName.isEmpty
                                ? account.type.defaultIconSystemName
                                : account.iconSystemName
                            Image(systemName: sfName)
                                .font(.system(size: 36))
                                .foregroundStyle(ColorPalette.foregroundColor(on: account.colorHex))
                                .frame(width: 72, height: 72)
                                .background(Color(hex: account.colorHex), in: Circle())
                        }
                    }

                    Text(account.balance.formatted(asCurrency: account.currency))
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(account.balance >= 0 ? Color.primary : Color.red)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)

                    Text("\(account.institution) · \(account.type.label)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }

            Section(lang["label.details"]) {
                // Institution avec logo
                HStack(spacing: 10) {
                    BankLogoView(domain: BankDirectory.domain(for: account.institution), size: 28, cornerRadius: 6)
                    Text(account.institution)
                        .foregroundStyle(.primary)
                    Spacer()
                }
                LabeledContent(lang["label.currency"]) {
                    Text("\(account.currency) — \(Currencies.info(for: account.currency).nameFR)")
                }
                LabeledContent(lang["account.initialBalance"]) {
                    Text(account.initialBalance.formatted(asCurrency: account.currency))
                }
                if let notes = account.notes, !notes.isEmpty {
                    LabeledContent(lang["label.notes"]) {
                        Text(notes).multilineTextAlignment(.trailing)
                    }
                }
            }

            if let regType = account.registeredProfile?.registeredType {
                registeredRoomSection(regType)
                registeredEntriesSection()
            }

            Section("\(lang["tx.title"]) (\(sortedTransactions.count))") {
                if sortedTransactions.isEmpty {
                    Text(lang["account.noTransactions"])
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sortedTransactions) { tx in
                        NavigationLink {
                            AddEditTransactionView(mode: .edit(tx))
                        } label: {
                            TransactionRow(transaction: tx)
                        }
                    }
                    .onDelete(perform: deleteTransactions)
                }
            }

            Section {
                Button {
                    confirmArchive = true
                } label: {
                    Label(account.isArchived ? lang["action.unarchive"] : lang["account.title"],
                          systemImage: account.isArchived ? "tray.and.arrow.up" : "archivebox")
                        .foregroundStyle(.orange)
                }
            } footer: {
                Text(lang["account.archiveFooter"])
            }
        }
        .navigationTitle(account.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showAddTransaction = true
                    } label: {
                        Label(lang["account.newTransaction"], systemImage: "plus")
                    }
                    Button {
                        showAddTransfer = true
                    } label: {
                        Label(lang["transfer.create"], systemImage: "arrow.left.arrow.right")
                    }
                    Button {
                        showEdit = true
                    } label: {
                        Label(lang["account.edit"], systemImage: "pencil")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showEdit) {
            AddEditAccountView(mode: .edit(account))
        }
        .sheet(isPresented: $showAddTransaction) {
            NavigationStack {
                AddEditTransactionView(mode: .create, preselectedAccount: account)
            }
        }
        .sheet(isPresented: $showAddTransfer) {
            AddTransferView(preselectedSource: account)
        }
        .sheet(isPresented: $showRoomPlan) {
            if let type = account.registeredProfile?.registeredType {
                RegisteredRoomPlanView(type: type, existing: registeredPlan)
            }
        }
        .sheet(isPresented: $showAddEntry) {
            AddRegisteredEntryView(account: account)
        }
        .confirmationDialog(
            account.isArchived ? lang["account.unarchivePrompt"] : lang["account.archivePrompt"],
            isPresented: $confirmArchive,
            titleVisibility: .visible
        ) {
            Button(account.isArchived ? lang["action.unarchive"] : lang["action.archive"]) {
                account.isArchived.toggle()
                try? context.save()
                if account.isArchived {
                    dismiss()
                }
            }
            Button(lang["action.cancel"], role: .cancel) {}
        }
    }

    private var registeredPlan: RegisteredRoomPlan? {
        guard let type = account.registeredProfile?.registeredType else { return nil }
        return allPlans.first { $0.registeredType == type }
    }

    @ViewBuilder
    private func registeredRoomSection(_ type: RegisteredType) -> some View {
        Section {
            if let plan = registeredPlan,
               let result = RegisteredRoomService.availableRoom(type: type, plan: plan, accounts: allAccounts) {
                LabeledContent(lang["reg.room.available"]) {
                    Text(result.availableRoom.formatted(asCurrency: account.currency))
                        .fontWeight(.semibold)
                        .foregroundStyle(result.isOverContributed ? Color.red : Color.primary)
                }
                if result.isOverContributed {
                    Label("\(lang["reg.room.over"]) : \(result.excess.formatted(asCurrency: account.currency))",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.red)
                }
                LabeledContent(lang["reg.anchor.label"]) {
                    Text("\(plan.anchorAmount.formatted(asCurrency: account.currency)) · \(String(plan.anchorYear))")
                }
                Button(lang["reg.anchor.edit"]) { showRoomPlan = true }
            } else {
                Button {
                    showRoomPlan = true
                } label: {
                    Label(lang["reg.room.configure"], systemImage: "slider.horizontal.3")
                }
            }
            Button {
                showAddEntry = true
            } label: {
                Label(lang["reg.entry.add"], systemImage: "plus.circle")
            }
        } header: {
            Text("\(lang["reg.room.section"]) · \(type.label)")
        } footer: {
            Text(lang["reg.room.sharedFooter"])
        }
    }

    private var sortedRegisteredEntries: [RegisteredEntry] {
        (account.registeredEntries ?? []).sorted { $0.date > $1.date }
    }

    @ViewBuilder
    private func registeredEntriesSection() -> some View {
        let entries = sortedRegisteredEntries
        if !entries.isEmpty {
            Section("\(lang["reg.entry.listTitle"]) (\(entries.count))") {
                ForEach(entries) { e in
                    HStack(spacing: 12) {
                        Image(systemName: e.kind == .contribution ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                            .foregroundStyle(e.kind == .contribution ? Color.green : Color.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.kind.label)
                            Text(e.date.formatted(.dateTime.day().month().year()))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(e.amount.formatted(asCurrency: account.currency)).fontWeight(.medium)
                    }
                }
                .onDelete(perform: deleteRegisteredEntries)
            }
        }
    }

    private func deleteRegisteredEntries(at offsets: IndexSet) {
        let entries = sortedRegisteredEntries
        for i in offsets { context.delete(entries[i]) }
        try? context.save()
    }

    private func deleteTransactions(at offsets: IndexSet) {
        let toDelete = offsets.map { sortedTransactions[$0] }
        for tx in toDelete {
            context.delete(tx)
        }
        account.recalculateBalance()
        try? context.save()
    }
}
