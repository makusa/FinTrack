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
    @State private var showAddRESPContribution = false
    @State private var editingTransaction: Transaction?

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
                    Text("\(account.currency) — \(Currencies.info(for: account.currency).name)")
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
            }
            if account.respProfile != nil {
                respGrantSection()
                respContributionsSection()
            }

            Section("\(lang["tx.title"]) (\(sortedTransactions.count))") {
                if sortedTransactions.isEmpty {
                    Text(lang["account.noTransactions"])
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sortedTransactions) { tx in
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
        .sheet(item: $editingTransaction) { tx in
            NavigationStack {
                AddEditTransactionView(mode: .edit(tx))
            }
        }
        .sheet(isPresented: $showAddTransfer) {
            AddTransferView(preselectedSource: account)
        }
        .sheet(isPresented: $showAddRESPContribution) {
            AddRESPContributionView(account: account)
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
            } else {
                Text(lang["reg.room.noAnchor"])
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("\(lang["reg.room.section"]) · \(type.label)")
        } footer: {
            Text(lang["reg.room.accountFooter"])
        }
    }

    @ViewBuilder
    private func respGrantSection() -> some View {
        if let profile = account.respProfile,
           let r = RESPGrantService.evaluate(account: account) {
            Section {
                if r.suggestedContributionThisYear > 0 {
                    LabeledContent(lang["resp.suggested"]) {
                        Text(r.suggestedContributionThisYear.formatted(asCurrency: account.currency))
                            .fontWeight(.semibold)
                            .foregroundStyle(.green)
                    }
                } else if r.isPastGrantAge {
                    Label(lang["resp.pastAge"], systemImage: "clock.badge.xmark")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                LabeledContent(lang["resp.cesg"]) {
                    Text("\(r.cesg.earned.formatted(asCurrency: account.currency)) / \(RESPGrantProgram.cesg.lifetimeMax.formatted(asCurrency: account.currency))")
                }
                if profile.quebecResident {
                    LabeledContent(lang["resp.iqee"]) {
                        Text("\(r.iqee.earned.formatted(asCurrency: account.currency)) / \(RESPGrantProgram.iqee.lifetimeMax.formatted(asCurrency: account.currency))")
                    }
                }

                LabeledContent(lang["resp.contributed"]) {
                    Text("\(r.totalContributed.formatted(asCurrency: account.currency)) / \(RESPGrantCalculator.lifetimeContributionLimit.formatted(asCurrency: account.currency))")
                        .foregroundStyle(r.isOverContributed ? Color.red : Color.primary)
                }
                if r.isOverContributed {
                    Label("\(lang["resp.over"]) : \(r.contributionExcess.formatted(asCurrency: account.currency))",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("\(lang["resp.section"]) · \(profile.beneficiaryName.isEmpty ? lang["resp.beneficiary.section"] : profile.beneficiaryName)")
            } footer: {
                Text(lang["resp.section.footer"])
            }
        }
    }



    private var sortedRESPContributions: [RESPContribution] {
        (account.respContributions ?? []).sorted { $0.date > $1.date }
    }

    @ViewBuilder
    private func respContributionsSection() -> some View {
        Section("\(lang["resp.contributed"]) (\(sortedRESPContributions.count))") {
            Button {
                showAddRESPContribution = true
            } label: {
                Label(lang["resp.entry.add"], systemImage: "plus.circle")
            }
            ForEach(sortedRESPContributions) { c in
                HStack(spacing: 12) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(Color.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.note.isEmpty ? lang["resp.contributed"] : c.note)
                        Text(c.date.formatted(.dateTime.day().month().year()))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(c.amount.formatted(asCurrency: account.currency)).fontWeight(.medium)
                }
            }
            .onDelete(perform: deleteRESPContributions)
        }
    }

    private func deleteRESPContributions(at offsets: IndexSet) {
        let items = sortedRESPContributions
        for i in offsets {
            let c = items[i]
            if let pairId = c.transferPairId {
                deleteLinkedTransfer(pairId)
            }
            context.delete(c)
        }
        try? context.save()
    }

    /// Deletes the cash transfer (both legs sharing `pairId`) that a registered
    /// entry created via the "also move the money" option, and refreshes the
    /// affected account balances.
    private func deleteLinkedTransfer(_ pairId: UUID) {
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate<Transaction> { $0.transferPairId == pairId }
        )
        let legs = (try? context.fetch(descriptor)) ?? []
        let affected = Set(legs.compactMap { $0.account })
        for leg in legs { context.delete(leg) }
        for acc in affected { acc.recalculateBalance() }
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
