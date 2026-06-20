//
//  AddRegisteredEntryView.swift
//  FinTrack
//
//  Logs a contribution or withdrawal on a registered account, with a live
//  over-contribution check (room shown as you type) and a mandatory confirm
//  if a contribution would exceed the available room.
//
//  A RegisteredEntry tracks ROOM only — it is not a cash transaction. Record
//  the actual money movement separately as a transfer if desired (room != balance).
//

import SwiftUI
import SwiftData

struct AddRegisteredEntryView: View {
    @Environment(\.modelContext) private var context
    @Environment(LanguageManager.self) private var lang
    @Environment(\.dismiss) private var dismiss

    let account: Account

    @Query private var allPlans: [RegisteredRoomPlan]
    @Query private var allAccounts: [Account]

    @State private var kind: RegisteredEntryKind = .contribution
    @State private var amountText: String = ""
    @State private var date: Date = .now
    @State private var note: String = ""
    @State private var showOverConfirm = false

    private var type: RegisteredType? { account.registeredProfile?.registeredType }
    private var plan: RegisteredRoomPlan? {
        guard let type else { return nil }
        return allPlans.first { $0.registeredType == type }
    }
    private var currency: String { account.currency }
    private var amount: Decimal { parseDecimal(amountText) ?? 0 }
    private var canSave: Bool { amount > 0 }

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
        let entry = RegisteredEntry(
            kind: kind,
            amount: amount,
            date: date,
            note: note.trimmingCharacters(in: .whitespaces)
        )
        entry.account = account
        context.insert(entry)
        try? context.save()
        dismiss()
    }

    private func parseDecimal(_ s: String) -> Decimal? {
        Decimal(string: s.replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces))
    }
}
