//
//  AccountDetailView.swift
//  FinTrack
//

import SwiftUI
import SwiftData

struct AccountDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Bindable var account: Account

    @State private var showEdit = false
    @State private var showAddTransaction = false
    @State private var confirmArchive = false

    private var sortedTransactions: [Transaction] {
        account.transactions.sorted { $0.date > $1.date }
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    Image(systemName: account.iconSystemName)
                        .font(.system(size: 36))
                        .foregroundStyle(.white)
                        .frame(width: 72, height: 72)
                        .background(Color(hex: account.colorHex), in: Circle())

                    Text(account.balance.formatted(asCurrency: account.currency))
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(account.balance >= 0 ? Color.primary : Color.red)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)

                    Text("\(account.institution) · \(account.type.labelFR)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }

            Section("Détails") {
                LabeledContent("Devise") {
                    Text("\(account.currency) — \(Currencies.info(for: account.currency).nameFR)")
                }
                LabeledContent("Solde initial") {
                    Text(account.initialBalance.formatted(asCurrency: account.currency))
                }
                if let notes = account.notes, !notes.isEmpty {
                    LabeledContent("Notes") {
                        Text(notes).multilineTextAlignment(.trailing)
                    }
                }
            }

            Section("Transactions (\(sortedTransactions.count))") {
                if sortedTransactions.isEmpty {
                    Text("Aucune transaction sur ce compte.")
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
                    Label(account.isArchived ? "Désarchiver" : "Archiver le compte",
                          systemImage: account.isArchived ? "tray.and.arrow.up" : "archivebox")
                        .foregroundStyle(.orange)
                }
            } footer: {
                Text("L'archivage masque le compte sans supprimer ses transactions. Les soldes globaux ne tiennent plus compte d'un compte archivé.")
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
                        Label("Nouvelle transaction", systemImage: "plus")
                    }
                    Button {
                        showEdit = true
                    } label: {
                        Label("Modifier le compte", systemImage: "pencil")
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
        .confirmationDialog(
            account.isArchived ? "Désarchiver ce compte ?" : "Archiver ce compte ?",
            isPresented: $confirmArchive,
            titleVisibility: .visible
        ) {
            Button(account.isArchived ? "Désarchiver" : "Archiver") {
                account.isArchived.toggle()
                try? context.save()
                if account.isArchived {
                    dismiss()
                }
            }
            Button("Annuler", role: .cancel) {}
        }
    }

    private func deleteTransactions(at offsets: IndexSet) {
        let toDelete = offsets.map { sortedTransactions[$0] }
        for tx in toDelete {
            context.delete(tx)
        }
        try? context.save()
    }
}
