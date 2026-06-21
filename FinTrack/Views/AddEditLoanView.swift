//
//  AddEditLoanView.swift
//  FinTrack
//

import SwiftUI
import SwiftData

enum LoanEditorMode {
    case create
    case edit(Loan)
}

struct AddEditLoanView: View {
    @Environment(\.modelContext) private var context
    @Environment(LanguageManager.self) private var lang
    @Environment(ExchangeRateManager.self) private var rates
    @Environment(\.dismiss) private var dismiss

    let mode: LoanEditorMode

    /// Currencies offered in the picker: the user's tracked list, plus this
    /// item's own currency if it's no longer tracked (so it's never lost).
    private var pickerCurrencies: [CurrencyInfo] {
        var list = rates.activeCurrencyInfos
        if !list.contains(where: { $0.code == currency }) {
            list.append(Currencies.info(for: currency))
        }
        return list
    }

    @Query(filter: #Predicate<Account> { !$0.isArchived },
           sort: \Account.createdAt, order: .forward)
    private var accounts: [Account]

    // MARK: Form state

    @State private var label: String = ""
    @State private var lenderName: String = ""
    @State private var type: LoanType = .mortgage
    @State private var currency: String = Currencies.default
    @State private var principalText: String = ""
    @State private var rateText: String = ""
    @State private var termYears: Int = LoanType.mortgage.defaults.termYears
    @State private var termExtraMonths: Int = LoanType.mortgage.defaults.termExtraMonths
    @State private var frequency: LoanPaymentFrequency = LoanType.mortgage.defaults.frequency
    @State private var compounding: LoanCompounding = LoanType.mortgage.defaults.compounding
    @State private var firstPaymentDate: Date = Calendar.current.date(byAdding: .month, value: 1, to: .now) ?? .now
    @State private var selectedAccount: Account?
    @State private var notes: String = ""
    @State private var showAdvanced: Bool = false
    @State private var createRecurring: Bool = true
    @State private var showDeleteConfirm: Bool = false

    @State private var notifEnabled: Bool = false
    @State private var notifDaysBefore: Int = 3

    @FocusState private var principalFocused: Bool

    private var isEditing: Bool { if case .edit = mode { return true }; return false }
    private var navTitle: String { isEditing ? lang["loan.edit"] : lang["loan.create"] }

    private var termMonths: Int { termYears * 12 + termExtraMonths }

    private var principal: Double? {
        Double(principalText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
    }
    private var annualRate: Double? {
        Double(rateText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
    }

    private var calculator: LoanCalculator? {
        guard let p = principal, p > 0,
              let r = annualRate, r > 0,
              termMonths > 0 else { return nil }
        return LoanCalculator(
            principal: p,
            annualRatePercent: r,
            termMonths: termMonths,
            frequency: frequency,
            compounding: compounding,
            firstPaymentDate: firstPaymentDate
        )
    }

    private var canSave: Bool {
        !label.trimmingCharacters(in: .whitespaces).isEmpty
            && principal != nil
            && annualRate != nil
            && termMonths > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                identitySection
                amountsSection
                scheduleSection
                if showAdvanced { advancedSection }
                accountSection
                if calculator != nil { summarySection }
                recurringSection
                notesSection
                notificationSection

                if isEditing { deleteSection }
            }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading)  { Button(lang["action.cancel"]) { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(lang["action.save"]) { save() }
                        .disabled(!canSave)
                        .fontWeight(.semibold)
                }
            }
            .confirmationDialog(lang["loan.delete"], isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button(lang["action.delete"], role: .destructive) { deleteIfEditing() }
                Button(lang["action.cancel"], role: .cancel) {}
            }
            .onAppear(perform: loadIfEditing)
            .onChange(of: type) { _, newType in
                guard !isEditing else { return }
                // Apply all market-appropriate defaults for the selected loan type
                let d = newType.defaults
                termYears       = d.termYears
                termExtraMonths = d.termExtraMonths
                frequency       = d.frequency
                compounding     = d.compounding
            }
        }
    }

    // MARK: - Sections

    private var identitySection: some View {
        Section(lang["loan.identify"]) {
            TextField(lang["loan.labelPlaceholder"], text: $label)

            Picker(lang["label.type"], selection: $type) {
                ForEach(LoanType.allCases) { t in
                    Label(t.label, systemImage: t.iconSystemName).tag(t)
                }
            }

            InstitutionPickerField(text: $lenderName, placeholder: lang["loan.lenderPlaceholder"])

            Picker(lang["label.currency"], selection: $currency) {
                ForEach(pickerCurrencies) { c in
                    Text("\(c.code) — \(c.nameFR)").tag(c.code)
                }
            }
        }
    }

    private var amountsSection: some View {
        Section {
            // Principal — big field
            HStack {
                Text(lang["loan.principal"])
                Spacer()
                TextField("0", text: $principalText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .focused($principalFocused)
                    .frame(maxWidth: 160)
                Text(Currencies.info(for: currency).symbol)
                    .foregroundStyle(.secondary)
            }

            // Interest rate
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(lang["loan.annualRate"])
                    Text(lang["loan.annualRate.sub"])
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                TextField("0,00", text: $rateText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 80)
                Text("%")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(lang["loan.amountRate"])
        }
    }

    private var scheduleSection: some View {
        Section(lang["loan.duration"]) {
            // Term — years + months
            HStack {
                Text(lang["loan.term"])
                Spacer()
                Picker("Années", selection: $termYears) {
                    ForEach(0...35, id: \.self) { y in
                        Text(y == 1 ? "1 an" : "\(y) ans").tag(y)
                    }
                }
                .pickerStyle(.wheel)
                .frame(width: 90, height: 80)
                .clipped()

                Picker("Mois", selection: $termExtraMonths) {
                    ForEach(0...11, id: \.self) { m in
                        Text(m == 0 ? "0 mois" : "\(m) mois").tag(m)
                    }
                }
                .pickerStyle(.wheel)
                .frame(width: 90, height: 80)
                .clipped()
            }

            Picker(lang["loan.paymentFreq"], selection: $frequency) {
                ForEach(LoanPaymentFrequency.allCases) { f in
                    Text(f.label).tag(f)
                }
            }

            DatePicker(lang["loan.firstPayment"], selection: $firstPaymentDate, displayedComponents: .date)

            Button {
                withAnimation { showAdvanced.toggle() }
            } label: {
                HStack {
                    Text(showAdvanced ? lang["label.hideAdvanced"] : lang["label.advanced"])
                        .font(.callout)
                    Spacer()
                    Image(systemName: showAdvanced ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private var advancedSection: some View {
        Section {
            Picker("Capitalisation des intérêts", selection: $compounding) {
                ForEach(LoanCompounding.allCases) { c in Text(c.label).tag(c) }
            }
        } header: {
            Text(lang["loan.compound.section"])
        } footer: {
            Text(lang["loan.compound.footer"])
        }
    }

    private var accountSection: some View {
        Section(lang["loan.debitAccount"]) {
            if accounts.isEmpty {
                Text(lang["loan.noAccount"])
                    .foregroundStyle(.secondary)
            } else {
                Picker(lang["label.account"], selection: $selectedAccount) {
                    Text(lang["loan.noAccount"]).tag(Account?.none)
                    ForEach(accounts) { acc in
                        HStack {
                            Image(systemName: acc.iconSystemName)
                                .foregroundStyle(Color(hex: acc.colorHex))
                            Text(acc.name)
                        }
                        .tag(Optional(acc))
                    }
                }
            }
        }
    }

    // MARK: Live summary

    @ViewBuilder
    private var summarySection: some View {
        if let calc = calculator {
            Section {
                summaryRow(lang["label.payment"] + " " + frequency.label.lowercased(),
                           value: formatAmount(calc.paymentAmount),
                           highlight: true)

                if frequency == .biweeklyAccelerated {
                    let saved = calc.totalPayments - calc.effectivePayments
                    summaryRow("Versements économisés",
                               value: "\(saved) versements",
                               color: .green)
                }

                summaryRow(lang["loan.totalInterest"],
                           value: formatAmount(calc.totalInterest),
                           color: calc.totalInterest > calc.principal ? .red : .primary)

                summaryRow(lang["loan.totalPaid"],
                           value: formatAmount(calc.totalAmountPaid))

                summaryRow(lang["loan.estimatedEnd"],
                           value: calc.payoffDate.appFormattedLong())
            } header: {
                Text(lang["loan.summary"])
            } footer: {
                Text(lang["loan.summary.footer"])
            }
        }
    }

    private var recurringSection: some View {
        Section {
            Toggle(isOn: $createRecurring) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(lang["loan.createRecurring"])
                    Text(lang["loan.createRecurring.sub"])
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var notesSection: some View {
        Section(lang["label.notes"] + " " + lang["label.optional"]) {
            TextField("Numéro de contrat, courtier, etc.", text: $notes, axis: .vertical)
                .lineLimit(2...4)
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) { showDeleteConfirm = true } label: {
                Label(lang["loan.delete"], systemImage: "trash")
            }
        } footer: {
            Text(lang["loan.delete.footer"])
        }
    }

    // MARK: - Helpers

    private func summaryRow(_ title: String, value: String,
                            highlight: Bool = false, color: Color = .primary) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(highlight ? .primary : .secondary)
            Spacer()
            Text(value)
                .font(highlight ? .body.weight(.bold) : .body.weight(.medium))
                .foregroundStyle(highlight ? Color.accentColor : color)
        }
    }

    private func formatAmount(_ v: Double) -> String {
        Decimal(v).formatted(asCurrency: currency)
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

    // MARK: - Logic

    private func loadIfEditing() {
        guard case .edit(let loan) = mode else {
            selectedAccount = accounts.first
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { principalFocused = true }
            return
        }
        label = loan.label
        lenderName = loan.lenderName
        type = loan.type
        currency = loan.currency
        principalText = decimalToText(loan.originalPrincipal)
        rateText = decimalToText(loan.annualInterestRate)
        let y = loan.termMonths / 12
        let m = loan.termMonths % 12
        termYears = y
        termExtraMonths = m
        frequency = loan.frequency
        compounding = loan.compounding
        firstPaymentDate = loan.firstPaymentDate
        selectedAccount = loan.account
        notes = loan.notes ?? ""
    }

    private func save() {
        guard let p = principal, let r = annualRate else { return }

        let principalDecimal = Decimal(p)
        let rateDecimal      = Decimal(r)
        let trimLabel        = label.trimmingCharacters(in: .whitespaces)
        let trimLender       = lenderName.trimmingCharacters(in: .whitespaces)
        let trimNotes        = notes.trimmingCharacters(in: .whitespaces)

        switch mode {
        case .create:
            let loan = Loan(
                label: trimLabel,
                lenderName: trimLender,
                type: type,
                currency: currency,
                originalPrincipal: principalDecimal,
                annualInterestRate: rateDecimal,
                termMonths: termMonths,
                frequency: frequency,
                compounding: compounding,
                firstPaymentDate: firstPaymentDate,
                account: selectedAccount,
                notes: trimNotes.isEmpty ? nil : trimNotes
            )
            loan.notificationEnabled = notifEnabled
            loan.notificationDaysBefore = notifDaysBefore
            context.insert(loan)

            // Auto-create recurring transaction if requested
            if createRecurring, let calc = calculator {
                let amount = Decimal(calc.paymentAmount)
                let rule = RecurringTransaction(
                    title: trimLabel.isEmpty ? type.label : trimLabel,
                    amount: amount,
                    type: .expense,
                    frequency: frequency.recurringFrequency,
                    startDate: firstPaymentDate,
                    account: selectedAccount,
                    note: "Remboursement \(trimLender.isEmpty ? type.label : trimLender)",
                    payee: trimLender.isEmpty ? nil : trimLender,
                    isLoanPayment: true
                )
                context.insert(rule)
            }

        case .edit(let loan):
            loan.label = trimLabel
            loan.lenderName = trimLender
            loan.type = type
            loan.currency = currency
            loan.originalPrincipal = principalDecimal
            loan.annualInterestRate = rateDecimal
            loan.termMonths = termMonths
            loan.frequency = frequency
            loan.compounding = compounding
            loan.firstPaymentDate = firstPaymentDate
            loan.account = selectedAccount
            loan.notes = trimNotes.isEmpty ? nil : trimNotes
            loan.notificationEnabled = notifEnabled
            loan.notificationDaysBefore = notifDaysBefore
        }

        do {
            try context.save()
            // Generate all past occurrences synchronously BEFORE dismissing.
            // Using a Task (async) caused a race condition: the task ran after
            // the view was torn down, leading to silent failures.
            // applyPending is fast (arithmetic + DB inserts) — calling it
            // synchronously here matches the pattern in AddEditRecurringTransactionView.
            RecurringTransactionManager.applyPending(context: context)
            LoanPrepaymentManager.applyPending(context: context)
            // Notifications are non-critical — schedule them async
            let ctx = context
            Task { await NotificationManager.shared.scheduleAll(context: ctx) }
            dismiss()
        } catch {
            AppLogger.persistence.error("AddEditLoanView save failed: \(error, privacy: .private)")
        }
    }

    private func deleteIfEditing() {
        guard case .edit(let loan) = mode else { return }
        context.delete(loan)
        loan.notificationEnabled = notifEnabled
        loan.notificationDaysBefore = notifDaysBefore
        try? context.save()
        let ctx = context
        Task { await NotificationManager.shared.scheduleAll(context: ctx) }
        dismiss()
    }

    private func decimalToText(_ d: Decimal) -> String {
        return d.appFormattedForInput
    }
}
