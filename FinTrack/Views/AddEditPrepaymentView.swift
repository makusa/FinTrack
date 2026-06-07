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

    @Query(filter: #Predicate<Account> { !$0.isArchived },
           sort: \Account.createdAt, order: .forward)
    private var accounts: [Account]

    // MARK: Form state

    @State private var amountText: String = ""
    @State private var isRecurring: Bool = false
    @State private var startDate: Date = .now
    @State private var frequency: RecurrenceFrequency = .monthly
    @State private var hasEndDate: Bool = false
    @State private var endDate: Date = Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now
    @State private var note: String = ""
    @State private var selectedAccount: Account? = nil
    @State private var showDeleteConfirm: Bool = false

    @State private var notifEnabled: Bool = false
    @State private var notifDaysBefore: Int = 3

    @FocusState private var amountFocused: Bool

    // MARK: Helpers

    private var loan: Loan {
        switch mode {
        case .create(let l): return l
        case .edit(let p):   return p.loan ?? Loan(label: "", lenderName: "", type: .other,
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

    private var availableFrequencies: [RecurrenceFrequency] {
        [.weekly, .biweekly, .monthly, .quarterly, .yearly]
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                amountSection
                typeSection
                scheduleSection
                accountSection
                noteSection
                notificationSection
                if isEditing { deleteSection }
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

    // MARK: - Sections

    private var amountSection: some View {
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
    }

    private var typeSection: some View {
        Section {
            Picker(lang["label.type"], selection: $isRecurring) {
                Text(lang["prepayment.oneTime"]).tag(false)
                Text(lang["prepayment.recurring"]).tag(true)
            }
            .pickerStyle(.segmented)
        }
    }

    private var scheduleSection: some View {
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

                Toggle(lang["recurring.endDate"], isOn: $hasEndDate)

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
    }

    // Section compte source — header + footer avec la syntaxe labeled closures
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
                            let iconName = acc.iconSystemName.isEmpty
                                ? acc.type.defaultIconSystemName
                                : acc.iconSystemName
                            Image(systemName: iconName)
                                .foregroundStyle(Color(hex: acc.colorHex))
                        }
                        .tag(Optional(acc))
                    }
                }
            }
        } header: {
            Text(lang["prepayment.account.section"])
        } footer: {
            Text(lang["prepayment.account.footer"])
        }
    }

    private var noteSection: some View {
        Section(lang["label.notes"] + " " + lang["label.optional"]) {
            TextField(lang["label.note"], text: $note, axis: .vertical)
                .lineLimit(1...3)
        }
    }

    private var notificationSection: some View {
        Section {
            Toggle(lang["notification.enable"], isOn: $notifEnabled)
            if notifEnabled {
                Picker(lang["notification.daysBefore"], selection: $notifDaysBefore) {
                    ForEach(notificationDaysOptions, id: \.self) { d in
                        Text(d == 1 ? lang["notification.dayBefore.1"] : lang.f("notification.dayBefore.n", d)).tag(d)
                    }
                }
                .pickerStyle(.menu)
            }
        } header: {
            Label(lang["notification.section"], systemImage: "bell")
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label(lang["prepayment.deletePrompt"], systemImage: "trash")
            }
        }
    }

    // MARK: - Logic

    private func loadIfEditing() {
        guard case .edit(let prep) = mode else { return }
        notifEnabled      = prep.notificationEnabled
        notifDaysBefore   = prep.notificationDaysBefore
        amountText        = decimalToText(prep.amount)
        isRecurring       = prep.isRecurring
        startDate         = prep.startDate
        if let freq = prep.frequency { frequency = freq }
        if let ed = prep.endDate { endDate = ed; hasEndDate = true }
        note              = prep.note ?? ""
        selectedAccount   = prep.account
    }

    private func save() {
        guard let amt = amount, amt > 0 else { return }
        let trimmedNote = note.trimmingCharacters(in: .whitespaces)

        switch mode {
        case .create(let l):
            let prep = LoanPrepayment(
                amount:    amt,
                startDate: startDate,
                isRecurring: isRecurring,
                frequency: isRecurring ? frequency : nil,
                endDate:   isRecurring && hasEndDate ? endDate : nil,
                note:      trimmedNote.isEmpty ? nil : trimmedNote
            )
            prep.loan            = l
            prep.account         = selectedAccount
            prep.nextPostDate    = selectedAccount != nil ? startDate : nil
            prep.notificationEnabled    = notifEnabled
            prep.notificationDaysBefore = notifDaysBefore
            context.insert(prep)

        case .edit(let prep):
            prep.amount      = amt
            prep.startDate   = startDate
            prep.isRecurring = isRecurring
            prep.frequency   = isRecurring ? frequency : nil
            prep.endDate     = isRecurring && hasEndDate ? endDate : nil
            prep.note        = trimmedNote.isEmpty ? nil : trimmedNote
            prep.notificationEnabled    = notifEnabled
            prep.notificationDaysBefore = notifDaysBefore

            // Compare account identity to decide if nextPostDate must be reset.
            // Using ObjectIdentifier avoids depending on PersistentIdentifier state.
            let prevID = prep.account.map { ObjectIdentifier($0) }
            let newID  = selectedAccount.map { ObjectIdentifier($0) }
            if prevID != newID {
                prep.account      = selectedAccount
                prep.nextPostDate = selectedAccount != nil ? startDate : nil
            }
        }

        try? context.save()
        let ctx = context
        Task { @MainActor in
            LoanPrepaymentManager.applyPending(context: ctx)
            await NotificationManager.shared.scheduleAll(context: ctx)
        }
        dismiss()
    }

    private func deleteIfEditing() {
        guard case .edit(let prep) = mode else { return }
        let notifOn   = prep.notificationEnabled
        let notifDays = prep.notificationDaysBefore
        context.delete(prep)
        try? context.save()
        let ctx = context
        Task {
            await NotificationManager.shared.scheduleAll(context: ctx)
        }
        _ = notifOn; _ = notifDays   // suppress unused-variable warnings
        dismiss()
    }

    private func decimalToText(_ d: Decimal) -> String {
        return d.appFormattedForInput
    }
}
