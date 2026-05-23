//
//  AddEditPrepaymentView.swift
//  FinTrack
//

import SwiftUI
import SwiftData

enum PrepaymentEditorMode {
    case create(loan: Loan)
    case edit(LoanPrepayment)
}

struct AddEditPrepaymentView: View {
    @Environment(\.modelContext) private var context
    @Environment(LanguageManager.self) private var lang
    @Environment(\.dismiss) private var dismiss

    let mode: PrepaymentEditorMode

    // MARK: Form state

    @State private var amountText: String = ""
    @State private var isRecurring: Bool = false
    @State private var startDate: Date = .now
    @State private var frequency: RecurrenceFrequency = .monthly
    @State private var hasEndDate: Bool = false
    @State private var endDate: Date = Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now
    @State private var note: String = ""
    @State private var showDeleteConfirm: Bool = false

    @FocusState private var amountFocused: Bool

    private var loan: Loan {
        switch mode {
        case .create(let l): return l
        case .edit(let p): return p.loan ?? Loan(label: "", lenderName: "", type: .other,
                                                  currency: "CAD", originalPrincipal: 0,
                                                  annualInterestRate: 0, termMonths: 0,
                                                  frequency: .monthly, compounding: .monthly,
                                                  firstPaymentDate: .now)
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var amount: Decimal? {
        let normalized = amountText
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        return Decimal(string: normalized)
    }

    private var canSave: Bool {
        guard let amt = amount, amt > 0 else { return false }
        return true
    }

    // Frequencies relevant for prepayments
    private var availableFrequencies: [RecurrenceFrequency] {
        [.weekly, .biweekly, .monthly, .quarterly, .yearly]
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Amount
                Section {
                    HStack(spacing: 8) {
                        TextField("0", text: $amountText)
                            .font(.system(size: 40, weight: .light, design: .rounded))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.center)
                            .focused($amountFocused)
                        Text(Currencies.info(for: loan.currency).symbol)
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }

                // MARK: Type
                Section {
                    Picker(lang["label.type"], selection: $isRecurring.animation()) {
                        Text(lang["prepayment.oneTime"]).tag(false)
                        Text(lang["prepayment.recurring"]).tag(true)
                    }
                    .pickerStyle(.segmented)
                }

                // MARK: Schedule
                Section(lang["recurring.schedule"]) {
                    DatePicker(
                        isRecurring ? lang["prepayment.startDate.recurring"] : lang["prepayment.startDate.oneTime"],
                        selection: $startDate,
                        displayedComponents: .date
                    )

                    if isRecurring {
                        Picker(lang["label.frequency"], selection: $frequency) {
                            ForEach(availableFrequencies) { f in
                                Text(f.label).tag(f)
                            }
                        }

                        Toggle(lang["recurring.endDate"], isOn: $hasEndDate.animation())

                        if hasEndDate {
                            DatePicker(
                                lang["recurring.endDate"],
                                selection: $endDate,
                                in: startDate...,
                                displayedComponents: .date
                            )
                        }
                    }
                }

                // MARK: Note
                Section(lang["label.notes"] + " " + lang["label.optional"]) {
                    TextField(lang["label.note"], text: $note, axis: .vertical)
                        .lineLimit(1...3)
                }

                // MARK: Delete (edit mode)
                if isEditing {
                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label(lang["prepayment.deletePrompt"], systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? lang["prepayment.edit"] : lang["prepayment.create"])
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
            .confirmationDialog(
                lang["prepayment.deletePrompt"],
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button(lang["action.delete"], role: .destructive) { deleteIfEditing() }
                Button(lang["action.cancel"], role: .cancel) {}
            }
            .onAppear {
                loadIfEditing()
                if !isEditing {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        amountFocused = true
                    }
                }
            }
        }
    }

    // MARK: - Logic

    private func loadIfEditing() {
        guard case .edit(let prep) = mode else { return }
        amountText = decimalToText(prep.amount)
        isRecurring = prep.isRecurring
        startDate = prep.startDate
        if let freq = prep.frequency { frequency = freq }
        if let ed = prep.endDate { endDate = ed; hasEndDate = true }
        note = prep.note ?? ""
    }

    private func save() {
        guard let amt = amount, amt > 0 else { return }
        let trimmedNote = note.trimmingCharacters(in: .whitespaces)

        switch mode {
        case .create(let l):
            let prep = LoanPrepayment(
                amount: amt,
                startDate: startDate,
                isRecurring: isRecurring,
                frequency: isRecurring ? frequency : nil,
                endDate: isRecurring && hasEndDate ? endDate : nil,
                note: trimmedNote.isEmpty ? nil : trimmedNote
            )
            prep.loan = l
            context.insert(prep)

        case .edit(let prep):
            prep.amount = amt
            prep.startDate = startDate
            prep.isRecurring = isRecurring
            prep.frequency = isRecurring ? frequency : nil
            prep.endDate = isRecurring && hasEndDate ? endDate : nil
            prep.note = trimmedNote.isEmpty ? nil : trimmedNote
        }

        try? context.save()
        dismiss()
    }

    private func deleteIfEditing() {
        guard case .edit(let prep) = mode else { return }
        context.delete(prep)
        try? context.save()
        dismiss()
    }

    private func decimalToText(_ d: Decimal) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "fr_CA")
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 0
        f.usesGroupingSeparator = false
        return f.string(from: NSDecimalNumber(decimal: d)) ?? "\(d)"
    }
}
