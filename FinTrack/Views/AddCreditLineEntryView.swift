//
//  AddCreditLineEntryView.swift
//  FinTrack
//

import SwiftUI
import SwiftData

struct AddCreditLineEntryView: View {
    @Environment(\.modelContext) private var context
    @Environment(LanguageManager.self) private var lang
    @Environment(\.dismiss)      private var dismiss

    let creditLine: CreditLine
    let defaultType: CreditLineEntryType

    @Query(filter: #Predicate<Account> { !$0.isArchived },
           sort: \Account.createdAt, order: .forward)
    private var accounts: [Account]

    @State private var entryType: CreditLineEntryType
    @State private var amountText       = ""
    @State private var date             = Date()
    @State private var note             = ""
    @State private var selectedAccount: Account? = nil

    @FocusState private var amountFocused: Bool

    init(creditLine: CreditLine, defaultType: CreditLineEntryType = .repayment) {
        self.creditLine  = creditLine
        self.defaultType = defaultType
        _entryType = State(initialValue: defaultType)
    }

    private var amount: Decimal? {
        Decimal(string: amountText
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces))
    }

    private var canSave: Bool { amount != nil && amount! > 0 }

    private var accentColor: Color {
        switch entryType {
        case .draw:            return .red
        case .repayment:       return .green
        case .interestAccrual: return .orange
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                typeSection
                amountSection
                detailsSection
                accountSection
                if let amt = amount, amt > 0 { previewSection(amt: amt) }
            }
            .navigationTitle(entryType == .draw
                             ? lang["cl.newDraw"]
                             : lang["cl.newRepayment"])
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(lang["action.cancel"]) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(lang["action.save"]) { save() }
                        .disabled(!canSave)
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                // Pre-select the account linked to the credit line if any
                selectedAccount = creditLine.account
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    amountFocused = true
                }
            }
        }
    }

    // MARK: - Sections

    private var typeSection: some View {
        Section {
            Picker("Type", selection: $entryType) {
                Text(lang["cl.entry.draw"]).tag(CreditLineEntryType.draw)
                Text(lang["cl.entry.repayment"]).tag(CreditLineEntryType.repayment)
            }
            .pickerStyle(.segmented)
        }
    }

    private var amountSection: some View {
        Section {
            HStack(spacing: 6) {
                Text(entryType == .draw ? "+" : "−")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(accentColor)
                TextField("0", text: $amountText)
                    .font(.system(size: 44, weight: .light, design: .rounded))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .focused($amountFocused)
                    .frame(maxWidth: .infinity)
                Text(Currencies.info(for: creditLine.currency).symbol)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 50, alignment: .leading)
            }
            .padding(.vertical, 8)
        }
    }

    private var detailsSection: some View {
        Section(lang["label.details"]) {
            DatePicker(lang["label.date"], selection: $date, displayedComponents: .date)
            TextField(lang["label.note"], text: $note, axis: .vertical)
                .lineLimit(1...3)
        }
    }

    // Account picker — shows which account is debited (repayment) or credited (draw)
    private var accountSection: some View {
        Section {
            if accounts.isEmpty {
                Text(lang["loan.noAccount"])
                    .foregroundStyle(.secondary)
            } else {
                Picker(lang["label.account"], selection: $selectedAccount) {
                    Text(lang["prepayment.account.none"]).tag(Account?.none)
                    ForEach(accounts) { acc in
                        Label {
                            HStack {
                                Text(acc.name)
                                Text("(\(acc.currency))")
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: acc.iconSystemName.isEmpty
                                  ? acc.type.defaultIconSystemName
                                  : acc.iconSystemName)
                                .foregroundStyle(Color(hex: acc.colorHex))
                        }
                        .tag(Optional(acc))
                    }
                }
            }
        } header: {
            Text(entryType == .draw
                 ? lang["cl.entry.account.draw"]
                 : lang["cl.entry.account.repayment"])
        } footer: {
            Text(entryType == .draw
                 ? lang["cl.entry.account.draw.footer"]
                 : lang["cl.entry.account.repayment.footer"])
        }
    }

    @ViewBuilder
    private func previewSection(amt: Decimal) -> some View {
        Section(lang["cl.preview"]) {
            let newBalance = entryType == .draw
                ? creditLine.currentBalance + amt
                : max(0, creditLine.currentBalance - amt)
            let newAvailable = max(0, creditLine.creditLimit - newBalance)
            HStack {
                Text(lang["cl.balanceUsed"]).foregroundStyle(.secondary)
                Spacer()
                Text(newBalance.formatted(asCurrency: creditLine.currency))
                    .foregroundStyle(newBalance > creditLine.creditLimit ? .red : .primary)
            }
            HStack {
                Text(lang["cl.available"]).foregroundStyle(.secondary)
                Spacer()
                Text(newAvailable.formatted(asCurrency: creditLine.currency))
                    .foregroundStyle(.green)
            }
            if let acc = selectedAccount {
                Divider()
                HStack {
                    Text(acc.name).foregroundStyle(.secondary)
                    Spacer()
                    let sign = entryType == .draw ? "+" : "−"
                    Text(sign + amt.formatted(asCurrency: creditLine.currency))
                        .foregroundStyle(entryType == .draw ? .green : .red)
                }
            }
        }
    }

    // MARK: - Save

    private func save() {
        guard let amt = amount, amt > 0 else { return }
        let trimNote = note.trimmingCharacters(in: .whitespaces)

        // 1. Create the CreditLineEntry (updates the credit line balance)
        let entry = CreditLineEntry(
            type: entryType,
            amount: amt,
            date: date,
            note: trimNote
        )
        entry.creditLine = creditLine
        entry.account    = selectedAccount
        context.insert(entry)

        // 2. Create the corresponding Transaction in the linked account (if any)
        if let acc = selectedAccount {
            // Repayment → expense (money leaves the account)
            // Draw      → income  (money arrives in the account)
            let txType: TransactionType = entryType == .draw ? .income : .expense
            let txNote = trimNote.isEmpty
                ? (entryType == .draw
                   ? lang["cl.entry.draw"] + " — " + creditLine.name
                   : lang["cl.entry.repayment"] + " — " + creditLine.name)
                : trimNote
            let tx = Transaction(
                amount:   amt,
                type:     txType,
                date:     date,
                account:  acc,
                category: nil,
                note:     txNote,
                payee:    creditLine.lenderName.isEmpty ? nil : creditLine.lenderName
            )
            context.insert(tx)
            acc.recalculateBalance()
        }

        try? context.save()
        dismiss()
    }
}
