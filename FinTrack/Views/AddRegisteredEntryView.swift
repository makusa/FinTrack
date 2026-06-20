//
//  AddRegisteredEntryView.swift
//  FinTrack
//
//  Logs a contribution or withdrawal on a registered account, with a live
//  over-contribution check (room shown as you type) and a mandatory confirm
//  if a contribution would exceed the available room.
//
//  A RegisteredEntry tracks ROOM. Optionally, the matching cash movement is
//  recorded as a linked transfer (debit + credit) so account balances reflect
//  it. The toggle defaults OFF for bank-synced accounts to avoid double counting.
//

import SwiftUI
import SwiftData

struct AddRegisteredEntryView: View {
    @Environment(\.modelContext) private var context
    @Environment(LanguageManager.self) private var lang
    @Environment(ExchangeRateManager.self) private var rates
    @Environment(\.dismiss) private var dismiss

    let account: Account

    @Query private var allPlans: [RegisteredRoomPlan]
    @Query private var allAccounts: [Account]

    @State private var kind: RegisteredEntryKind = .contribution
    @State private var amountText: String = ""
    @State private var date: Date = .now
    @State private var note: String = ""
    @State private var showOverConfirm = false
    @State private var alsoMoveCash = true
    @State private var counterparty: Account? = nil

    private var type: RegisteredType? { account.registeredProfile?.registeredType }
    private var plan: RegisteredRoomPlan? {
        guard let type else { return nil }
        return allPlans.first { $0.registeredType == type }
    }
    private var currency: String { account.currency }
    private var amount: Decimal { parseDecimal(amountText) ?? 0 }

    /// Other (non-archived) accounts this contribution/withdrawal can move cash with.
    private var transferableAccounts: [Account] {
        allAccounts.filter { !$0.isArchived && $0.persistentModelID != account.persistentModelID }
    }
    /// Heuristic: a bank-synced account already imports the cash movement, so we
    /// default the "also move the money" toggle OFF for it to avoid double counting.
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

    /// Over-contribution check for a contribution of the entered amount on `date`.
    private var overCheck: (over: Bool, excess: Decimal, roomBefore: Decimal)? {
        guard kind == .contribution, let type, let plan, amount > 0 else { return nil }
        return RegisteredRoomCalculator.overContributionCheck(
            type: type,
            anchorYear: plan.anchorYear,
            anchorAmount: plan.anchorAmount,
            lifetimeContributedAtAnchor: plan.lifetimeContributedAtAnchor,
            existingEntries: RegisteredRoomService.entries(forType: type, in: allAccounts),
            newContribution: amount,
            on: date
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(lang["reg.entry.kind"], selection: $kind) {
                        Text(lang["reg.entry.contribution"]).tag(RegisteredEntryKind.contribution)
                        Text(lang["reg.entry.withdrawal"]).tag(RegisteredEntryKind.withdrawal)
                    }
                    .pickerStyle(.segmented)
                }

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

                if let type {
                    if let result = RegisteredRoomService.availableRoom(type: type, plan: plan, accounts: allAccounts, asOf: date) {
                        Section {
                            LabeledContent(lang["reg.room.available"]) {
                                Text(result.availableRoom.formatted(asCurrency: currency))
                                    .foregroundStyle(result.availableRoom < 0 ? Color.red : Color.secondary)
                            }
                            if let check = overCheck, check.over {
                                VStack(alignment: .leading, spacing: 4) {
                                    Label("\(lang["reg.entry.overWarn"]) \(check.excess.formatted(asCurrency: currency))",
                                          systemImage: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.red)
                                    Text("\(lang["reg.entry.penalty"]) \(RegisteredRoomCalculator.estimatedMonthlyPenalty(excess: check.excess).formatted(asCurrency: currency))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } footer: {
                            if kind == .withdrawal && type == .celi {
                                Text(lang["reg.entry.withdrawNote"])
                            }
                        }
                    } else {
                        Section { Text(lang["reg.entry.noAnchor"]).font(.callout).foregroundStyle(.secondary) }
                    }
                }

                if !transferableAccounts.isEmpty {
                    Section {
                        Toggle(lang["reg.entry.moveCash"], isOn: $alsoMoveCash)
                        if alsoMoveCash {
                            Picker(kind == .contribution ? lang["reg.entry.fromAccount"] : lang["reg.entry.toAccount"],
                                   selection: $counterparty) {
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
                        if alsoMoveCash {
                            Text(lang["reg.entry.moveCashFooter"])
                        }
                    }
                }
            }
            .navigationTitle(lang["reg.entry.title"])
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
                if let check = overCheck {
                    Text("\(lang["reg.entry.overWarn"]) \(check.excess.formatted(asCurrency: currency))")
                }
            }
            .onAppear {
                if accountIsSynced { alsoMoveCash = false }
            }
        }
    }

    private func attemptSave() {
        if let check = overCheck, check.over {
            showOverConfirm = true
        } else {
            commit()
        }
    }

    private func commit() {
        // 1) Always record the room entry (drives contribution-room tracking).
        let entry = RegisteredEntry(
            kind: kind,
            amount: amount,
            date: date,
            note: note.trimmingCharacters(in: .whitespaces)
        )
        entry.account = account
        context.insert(entry)

        // 2) Optionally move the actual cash as a linked transfer (drives balances),
        //    and remember its pair id so deleting this entry can undo the transfer.
        if movesCash, let other = counterparty {
            entry.transferPairId = makeTransfer(with: other)
        }

        try? context.save()
        dismiss()
    }

    /// Creates a debit + credit Transaction pair (linked by transferPairId) so the
    /// account balances reflect the contribution/withdrawal. Mirrors AddTransferView.
    /// Contribution: money flows other -> registered account. Withdrawal: the reverse.
    private func makeTransfer(with other: Account) -> UUID {
        let pairId = UUID()
        let trimmedNote = note.trimmingCharacters(in: .whitespaces)

        // The entered amount is in the registered account's currency; its leg keeps it.
        let accountLeg = amount
        let otherLeg = (account.currency == other.currency)
            ? amount
            : rates.convert(amount, from: account.currency, to: other.currency)

        let src: Account
        let srcAmount: Decimal
        let dst: Account
        let dstAmount: Decimal
        if kind == .contribution {
            src = other;   srcAmount = otherLeg
            dst = account; dstAmount = accountLeg
        } else {
            src = account; srcAmount = accountLeg
            dst = other;   dstAmount = otherLeg
        }

        let debitNote  = trimmedNote.isEmpty ? "\(lang["transfer.to.label"]) \(dst.name)"   : trimmedNote
        let creditNote = trimmedNote.isEmpty ? "\(lang["transfer.from.label"]) \(src.name)" : trimmedNote

        let debit = Transaction(amount: srcAmount, type: .expense, date: date,
                                account: src, category: nil, note: debitNote, payee: dst.name)
        debit.transferPairId = pairId
        let credit = Transaction(amount: dstAmount, type: .income, date: date,
                                 account: dst, category: nil, note: creditNote, payee: src.name)
        credit.transferPairId = pairId

        context.insert(debit)
        context.insert(credit)
        src.recalculateBalance()
        dst.recalculateBalance()
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
