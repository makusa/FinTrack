//
//  AccountsView.swift
//  FinTrack
//

import SwiftUI
import SwiftData

struct AccountsView: View {
    @Environment(\.modelContext) private var context
    @Environment(LanguageManager.self) private var lang
    @Environment(ExchangeRateManager.self) private var rates

    @Query(filter: #Predicate<Account> { !$0.isArchived },
           sort: \Account.createdAt, order: .forward)
    private var activeAccounts: [Account]

    @Query(filter: #Predicate<Account> { $0.isArchived },
           sort: \Account.createdAt, order: .forward)
    private var archivedAccounts: [Account]

    @State private var showAddAccount = false
    @State private var showArchived = false

    var body: some View {
        NavigationStack {
            List {
                if activeAccounts.isEmpty {
                    Section {
                        ContentUnavailableView(
                            lang["account.noAccounts"],
                            systemImage: "building.columns",
                            description: Text(lang["account.noAccounts.sub"])
                        )
                    }
                } else {
                    Section(lang["account.myAccounts"]) {
                        ForEach(activeAccounts) { account in
                            NavigationLink {
                                AccountDetailView(account: account)
                            } label: {
                                accountRow(account)
                            }
                        }
                    }
                }

                if !archivedAccounts.isEmpty {
                    Section {
                        DisclosureGroup(isExpanded: $showArchived) {
                            ForEach(archivedAccounts) { account in
                                NavigationLink {
                                    AccountDetailView(account: account)
                                } label: {
                                    accountRow(account)
                                        .opacity(0.6)
                                }
                            }
                        } label: {
                            Text(lang.f("account.archived", archivedAccounts.count))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(lang["account.title"])
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddAccount = true
                    } label: {
                        Image(systemName: "plus.circle.fill").font(.title3)
                    }
                }
            }
            .sheet(isPresented: $showAddAccount) {
                AddEditAccountView(mode: .create)
            }
        }
    }

    private func accountRow(_ account: Account) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(hex: account.colorHex))
                    .frame(width: 40, height: 40)
                if let domain = account.bankDomain {
                    BankLogoView(domain: domain, size: 26, cornerRadius: 6)
                } else {
                    Image(systemName: account.iconSystemName)
                        .foregroundStyle(.white)
                        .font(.system(size: 17, weight: .semibold))
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                    .font(.body.weight(.medium))
                Text("\(account.institution) · \(account.type.label)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(account.balance.formatted(asCurrency: account.currency))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(account.balance >= 0 ? Color.primary : Color.red)
                if account.currency != rates.displayCurrency,
                   rates.showConvertedAmounts,
                   let converted = rates.convertedLabel(account.balance, from: account.currency, to: rates.displayCurrency) {
                    Text(converted)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text(account.currency)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    AccountsView()
        .modelContainer(for: [Account.self, Transaction.self, Category.self], inMemory: true)
}
