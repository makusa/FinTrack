//
//  AddRESPContributionView.swift
//  FinTrack
//
//  Logs a REEE/RESP contribution, with a live preview of the grant it earns
//  (CESG + IQEE) and a confirm if it pushes the beneficiary past the $50,000
//  lifetime contribution cap. Mirrors AddRegisteredEntryView.
//
//  A RESPContribution tracks the grant-eligible amount. Optionally the matching
//  cash movement is recorded as a linked transfer (debit + credit) so balances
//  reflect it; the toggle defaults OFF for bank-synced accounts.
//

import SwiftUI
import SwiftData

struct AddRESPContributionView: View {
    @Environment(\.modelContext) private var context
    @Environment(LanguageManager.self) private var lang
    @Environment(ExchangeRateManager.self) private var rates
    @Environment(\.dismiss) private var dismiss

    let account: Account

    @Query private var allAccounts: [Account]

    @State private var amountText: String = ""
    @State private var date: Date = .now
    @State private var note: String = ""
    @State private var showOverConfirm = false
    @State private var alsoMoveCash = true
    @State private var counterparty: Account? = nil

    private var profile: RESPProfile? { account.respProfile }
    private var currency: String { account.currency }
    private var amount: Decimal { parseDecimal(amountText) ?? 0 }

    private var transferableAccounts: [Account] {
        allAccounts.filter { !$0.isArchived && $0.persistentModelID != account.persistentModelID && $0.currency == account.currency }
    }
    private var accountIsSynced: Bool {
        (account.transactions ?? []).contains { $0.externalId != nil }
    }
    private var counterpartyCurrency: String { counterparty?.currency ?? currency }
    private var isCrossCurrency: Bool { counterpartyCurrency != currency }
    private var convertedCounterpartyAmount: Decimal? {
        guard amount > 0, isCrossCurrency else { return nil }
        return rates.convert(amount, from: currency, to: counterpartyCurrency)
    }
    private var movesCash: Bool { alsoMoveCash && !transferableAccounts.isEmpty }

    private var canSave: Bool {
        guard amount > 0 else { return false }
        return movesCash ? counterparty != nil : true
    }

    /// Marginal effect of this contribution: grant earned (CESG/IQEE) and whether
    /// it pushes total contributions past the $50,000 lifetime cap.
    private var preview: (cesg: Decimal, iqee: Decimal, over: Bool, excess: Decimal)? {
        guard let profile, amount > 0 else { return nil }
        let existing = (account.respContributions ?? []).map { $0.asData }
        let withNew = existing + [RESPContributionData(date: date, amount: amount)]
        let before = RESPGrantCalculator.evaluate(birthYear: profile.birthYear,
                                                  quebecResident: profile.quebecResident,
                                                  contributions: existing, asOf: date)
        let after = RESPGrantCalculator.evaluate(birthYear: profile.birthYear,
                                                 quebecResident: profile.quebecResident,
                                                 contributions: withNew, asOf: date)
        return (max(0, after.cesg.earned - before.cesg.earned),
                max(0, after.iqee.earned - before.iqee.earned),
                after.isOverContributed, after.contributionExcess)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text(lang["reg.entry.amount"])
                        Spacer()
                        TextField("0", text: $amountText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 140)
                        Text(Currencies.info(for: currency).symbol).foregroundStyle(.secondary)
                    }
                    DatePicker(lang["reg.entry.date"], selection: $date, displayedComponents: .date)
                    TextField(lang["reg.entry.note"], text: $note, axis: .vertical).lineLimit(1...3)
                }

                if let profile, let p = preview {
                    Section {
                        LabeledContent(lang["resp.entry.cesgEarned"]) {
                            Text(p.cesg.formatted(asCurrency: currency)).foregroundStyle(.green)
                        }
                        if profile.quebecResident {
                            LabeledContent(lang["resp.entry.iqeeEarned"]) {
                                Text(p.iqee.formatted(asCurrency: currency)).foregroundStyle(.green)
                            }
                        }
                        if p.over {
                            VStack(alignment: .leading, spacing: 4) {
                                Label("\(lang["reg.entry.overWarn"]) \(p.excess.formatted(asCurrency: currency))",
                                      systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.red)
                                Text("\(lang["reg.entry.penalty"]) \(RESPGrantCalculator.estimatedMonthlyPenalty(excess: p.excess).formatted(asCurrency: currency))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    } footer: {
                        Text(lang["resp.entry.grantFooter"])
                    }
                }

                if !transferableAccounts.isEmpty {
                    Section {
                        Toggle(lang["reg.entry.moveCash"], isOn: $alsoMoveCash)
                        if alsoMoveCash {
                            Picker(lang["reg.entry.fromAccount"], selection: $counterparty) {
                                Text(lang["reg.entry.chooseAccount"]).tag(Account?.none)
                                ForEach(transferableAccounts) { acc in
                                    accountPickerLabel(acc).tag(Optional(acc))
                                }
                            }
                            if isCrossCurrency, let conv = convertedCounterpartyAmount {
                                HStack {
                                    Image(systemName: "arrow.left.arrow.right")
                                        .font(.caption).foregroundStyle(.secondary)
                                    Text("≈ \(conv.formatted(asCurrency: counterpartyCurrency))")
                                        .font(.callout).foregroundStyle(.secondary)
                                    Spacer()
                                    Text(lang["transfer.crossCurrency.note"])
                                        .font(.caption2).foregroundStyle(.orange)
                                }
                            }
                        }
                    } footer: {
                        if alsoMoveCash { Text(lang["reg.entry.moveCashFooter"]) }
                    }
                }
            }
            .navigationTitle(lang["resp.entry.title"])
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(lang["action.cancel"]) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(lang["action.save"]) { attemptSave() }
                        .disabled(!canSave)
                        .fontWeight(.semibold)
                }
            }
            .confirmationDialog(lang["reg.entry.overConfirmTitle"],
                                isPresented: $showOverConfirm, titleVisibility: .visible) {
                Button(lang["reg.entry.saveAnyway"], role: .destructive) { commit() }
                Button(lang["action.cancel"], role: .cancel) {}
            } message: {
                if let p = preview {
                    Text("\(lang["reg.entry.overWarn"]) \(p.excess.formatted(asCurrency: currency))")
                }
            }
            .onAppear {
                if accountIsSynced { alsoMoveCash = false }
            }
        }
    }

    private func attemptSave() {
        if let p = preview, p.over { showOverConfirm = true } else { commit() }
    }

    private func commit() {
        let c = RESPContribution(amount: amount, date: date,
                                 note: note.trimmingCharacters(in: .whitespaces))
        c.account = account
        context.insert(c)
        if movesCash, let other = counterparty {
            c.transferPairId = makeTransfer(with: other)
        }
        try? context.save()
        dismiss()
    }

    /// Debit + credit pair (linked by transferPairId): cash flows other -> RESP
    /// account (a contribution always moves money into the plan).
    private func makeTransfer(with other: Account) -> UUID {
        let pairId = UUID()
        let trimmedNote = note.trimmingCharacters(in: .whitespaces)
        let accountLeg = amount
        let otherLeg = (account.currency == other.currency)
            ? amount
            : rates.convert(amount, from: account.currency, to: other.currency)

        let debitNote  = trimmedNote.isEmpty ? "\(lang["transfer.to.label"]) \(account.name)" : trimmedNote
        let creditNote = trimmedNote.isEmpty ? "\(lang["transfer.from.label"]) \(other.name)" : trimmedNote

        let debit = Transaction(amount: otherLeg, type: .expense, date: date,
                                account: other, category: nil, note: debitNote, payee: account.name)
        debit.transferPairId = pairId
        let credit = Transaction(amount: accountLeg, type: .income, date: date,
                                 account: account, category: nil, note: creditNote, payee: other.name)
        credit.transferPairId = pairId

        context.insert(debit)
        context.insert(credit)
        other.recalculateBalance()
        account.recalculateBalance()
        return pairId
    }

    private func accountPickerLabel(_ acc: Account) -> some View {
        HStack(spacing: 6) {
            Image(systemName: acc.iconSystemName)
                .foregroundStyle(Color(hex: acc.colorHex))
            Text(acc.name)
            Text("(\(acc.currency))").foregroundStyle(.secondary).font(.caption)
        }
    }

    private func parseDecimal(_ s: String) -> Decimal? {
        Decimal(string: s.replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces))
    }
}
