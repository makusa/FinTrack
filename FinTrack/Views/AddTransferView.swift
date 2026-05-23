//
//  AddTransferView.swift
//  FinTrack
//
//  Records a one-time transfer between two accounts.
//  Creates two linked Transaction records (debit + credit) sharing a transferPairId.
//

import SwiftUI
import SwiftData

struct AddTransferView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss)      private var dismiss
    @Environment(LanguageManager.self) private var lang
    @Environment(ExchangeRateManager.self) private var rates

    @Query(filter: #Predicate<Account> { !$0.isArchived }, sort: \Account.createdAt)
    private var accounts: [Account]

    // MARK: Pre-selection

    var preselectedSource: Account? = nil

    // MARK: Form state

    @State private var sourceAccount: Account? = nil
    @State private var destinationAccount: Account? = nil
    @State private var amountText: String = ""
    @State private var date: Date = .now
    @State private var note: String = ""
    @State private var showAmountMismatch: Bool = false

    @FocusState private var amountFocused: Bool

    // MARK: Derived

    private var amount: Decimal? {
        Decimal(string: amountText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
    }

    private var sourceCurrency: String   { sourceAccount?.currency      ?? Currencies.default }
    private var destCurrency:   String   { destinationAccount?.currency ?? Currencies.default }
    private var isCrossCurrency: Bool    { sourceCurrency != destCurrency }

    /// Converted amount in destination currency for preview.
    private var convertedAmount: Decimal? {
        guard let a = amount, isCrossCurrency else { return nil }
        return rates.convert(a, from: sourceCurrency, to: destCurrency)
    }

    private var canSave: Bool {
        guard let a = amount, a > 0 else { return false }
        guard let src = sourceAccount, let dst = destinationAccount else { return false }
        return src.persistentModelID != dst.persistentModelID
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Amount
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 36, weight: .light))
                            .foregroundStyle(.tint)

                        TextField("0", text: $amountText)
                            .font(.system(size: 42, weight: .light, design: .rounded))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.center)
                            .focused($amountFocused)

                        Text(Currencies.info(for: sourceCurrency).symbol)
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)

                    // Cross-currency preview
                    if isCrossCurrency, let converted = convertedAmount {
                        HStack {
                            Image(systemName: "arrow.down")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("≈ \(converted.formatted(asCurrency: destCurrency))")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(lang["transfer.crossCurrency.note"])
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                }

                // MARK: Accounts
                Section(lang["transfer.accounts"]) {
                    // Source
                    Picker(lang["transfer.from"], selection: $sourceAccount) {
                        Text(lang["label.none"] + "…").tag(Account?.none)
                        ForEach(accounts) { a in
                            accountLabel(a).tag(Optional(a))
                        }
                    }
                    .onChange(of: sourceAccount) { _, _ in validateAccounts() }

                    // Arrow visual separator
                    HStack {
                        Spacer()
                        VStack(spacing: 2) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.tint)
                            Text(lang["transfer.to.label"])
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))

                    // Destination
                    Picker(lang["transfer.to"], selection: $destinationAccount) {
                        Text(lang["label.none"] + "…").tag(Account?.none)
                        ForEach(accounts.filter { $0.persistentModelID != sourceAccount?.persistentModelID }) { a in
                            accountLabel(a).tag(Optional(a))
                        }
                    }
                    .onChange(of: destinationAccount) { _, _ in validateAccounts() }

                    if showAmountMismatch {
                        Label(lang["transfer.sameAccount.error"], systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                // MARK: Details
                Section(lang["label.details"]) {
                    DatePicker(lang["label.date"], selection: $date, displayedComponents: .date)
                    TextField(lang["label.note"], text: $note, axis: .vertical)
                        .lineLimit(1...3)
                }

                // MARK: Summary preview
                if let src = sourceAccount, let dst = destinationAccount, let a = amount, a > 0 {
                    Section(lang["transfer.preview"]) {
                        transferPreviewRow(src: src, dst: dst, amount: a)
                    }
                    .listRowBackground(Color(.secondarySystemBackground))
                }
            }
            .navigationTitle(lang["transfer.create"])
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading)  { Button(lang["action.cancel"]) { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(lang["action.save"]) { save() }
                        .disabled(!canSave)
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                if let pre = preselectedSource { sourceAccount = pre }
                else if accounts.count >= 2 { sourceAccount = accounts.first }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { amountFocused = true }
            }
        }
    }

    // MARK: - Sub-views

    private func accountLabel(_ account: Account) -> some View {
        HStack(spacing: 6) {
            Image(systemName: account.iconSystemName)
                .foregroundStyle(Color(hex: account.colorHex))
            Text(account.name)
            Text("(\(account.currency))")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }

    private func transferPreviewRow(src: Account, dst: Account, amount: Decimal) -> some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(src.name).font(.callout.weight(.medium))
                    Text("− \(amount.formatted(asCurrency: src.currency))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red)
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(dst.name).font(.callout.weight(.medium))
                    if isCrossCurrency, let converted = convertedAmount {
                        Text("+ \(converted.formatted(asCurrency: dst.currency))")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.green)
                    } else {
                        Text("+ \(amount.formatted(asCurrency: dst.currency))")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.green)
                    }
                }
            }
        }
    }

    // MARK: - Logic

    private func validateAccounts() {
        if let s = sourceAccount, let d = destinationAccount,
           s.persistentModelID == d.persistentModelID {
            showAmountMismatch = true
            destinationAccount = nil
        } else {
            showAmountMismatch = false
        }
    }

    private func save() {
        guard let a = amount, a > 0,
              let src = sourceAccount,
              let dst = destinationAccount else { return }

        let trimmedNote = note.trimmingCharacters(in: .whitespaces)
        let pairId = UUID()

        // Debit: expense from source
        let debitNote  = trimmedNote.isEmpty ? "\(lang["transfer.to.label"]) \(dst.name)" : trimmedNote
        let creditNote = trimmedNote.isEmpty ? "\(lang["transfer.from.label"]) \(src.name)" : trimmedNote

        let debit = Transaction(
            amount: a,
            type: .expense,
            date: date,
            account: src,
            category: nil,
            note: debitNote,
            payee: dst.name
        )
        debit.transferPairId = pairId

        // Credit: income to destination (converted if cross-currency)
        let creditAmount = isCrossCurrency
            ? rates.convert(a, from: src.currency, to: dst.currency)
            : a

        let credit = Transaction(
            amount: creditAmount,
            type: .income,
            date: date,
            account: dst,
            category: nil,
            note: creditNote,
            payee: src.name
        )
        credit.transferPairId = pairId

        context.insert(debit)
        context.insert(credit)
        try? context.save()
        dismiss()
    }
}
