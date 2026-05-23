//
//  AddCreditLineEntryView.swift
//  FinTrack
//

import SwiftUI

struct AddCreditLineEntryView: View {
    @Environment(\.modelContext) private var context
    @Environment(LanguageManager.self) private var lang
    @Environment(\.dismiss)      private var dismiss

    let creditLine: CreditLine
    let defaultType: CreditLineEntryType

    @State private var entryType: CreditLineEntryType
    @State private var amountText = ""
    @State private var date = Date()
    @State private var note = ""

    @FocusState private var amountFocused: Bool

    init(creditLine: CreditLine, defaultType: CreditLineEntryType = .repayment) {
        self.creditLine  = creditLine
        self.defaultType = defaultType
        _entryType = State(initialValue: defaultType)
    }

    private var amount: Decimal? {
        Decimal(string: amountText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
    }

    private var canSave: Bool { amount != nil && (amount! > 0) }

    private var accentColor: Color {
        switch entryType {
        case .draw:            return .red
        case .repayment:       return .green
        case .interestAccrual: return .orange
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                // Type selector (draw or repayment only — interest is auto)
                Section {
                    Picker("Type", selection: $entryType) {
                        Text(lang["cl.entry.draw"]).tag(CreditLineEntryType.draw)
                        Text(lang["cl.entry.repayment"]).tag(CreditLineEntryType.repayment)
                    }
                    .pickerStyle(.segmented)
                }

                // Amount — large, focused
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
                            .font(.title3).foregroundStyle(.secondary)
                            .frame(minWidth: 50, alignment: .leading)
                    }
                    .padding(.vertical, 8)
                }

                // Context
                Section(lang["label.details"]) {
                    DatePicker(lang["label.date"], selection: $date, displayedComponents: .date)
                    TextField(lang["label.note"], text: $note, axis: .vertical)
                        .lineLimit(1...3)
                }

                // Balances after operation (live preview)
                if let amt = amount, amt > 0 {
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
                    }
                }
            }
            .navigationTitle(entryType == .draw ? lang["cl.newDraw"] : lang["cl.newRepayment"])
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading)  { Button(lang["action.cancel"]) { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(lang["action.save"]) { save() }
                        .disabled(!canSave).fontWeight(.semibold)
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { amountFocused = true }
            }
        }
    }

    private func save() {
        guard let amt = amount, amt > 0 else { return }
        let entry = CreditLineEntry(
            type: entryType, amount: amt, date: date,
            note: note.trimmingCharacters(in: .whitespaces)
        )
        entry.creditLine = creditLine
        context.insert(entry)
        try? context.save()
        dismiss()
    }
}
