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
    @Environment(\.dismiss) private var dismiss

    let mode: LoanEditorMode

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
    @State private var termYears: Int = 25
    @State private var termExtraMonths: Int = 0
    @State private var frequency: LoanPaymentFrequency = .monthly
    @State private var compounding: LoanCompounding = .semiAnnual
    @State private var firstPaymentDate: Date = Calendar.current.date(byAdding: .month, value: 1, to: .now) ?? .now
    @State private var selectedAccount: Account?
    @State private var notes: String = ""
    @State private var showAdvanced: Bool = false
    @State private var createRecurring: Bool = true
    @State private var showDeleteConfirm: Bool = false

    @FocusState private var principalFocused: Bool

    private var isEditing: Bool { if case .edit = mode { return true }; return false }
    private var navTitle: String { isEditing ? "Modifier le prêt" : "Nouveau prêt" }

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
                if isEditing { deleteSection }
            }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading)  { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Enregistrer") { save() }
                        .disabled(!canSave)
                        .fontWeight(.semibold)
                }
            }
            .confirmationDialog("Supprimer ce prêt ?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Supprimer", role: .destructive) { deleteIfEditing() }
                Button("Annuler", role: .cancel) {}
            }
            .onAppear(perform: loadIfEditing)
            .onChange(of: type) { _, newType in
                // Auto-switch compounding convention when type changes
                if !isEditing { compounding = newType.defaultCompounding }
            }
        }
    }

    // MARK: - Sections

    private var identitySection: some View {
        Section("Identification") {
            TextField("Libellé (ex. Hypothèque principale)", text: $label)

            Picker("Type", selection: $type) {
                ForEach(LoanType.allCases) { t in
                    Label(t.labelFR, systemImage: t.iconSystemName).tag(t)
                }
            }

            TextField("Prêteur (ex. Banque Nationale)", text: $lenderName)

            Picker("Devise", selection: $currency) {
                ForEach(Currencies.all) { c in
                    Text("\(c.code) — \(c.nameFR)").tag(c.code)
                }
            }
        }
    }

    private var amountsSection: some View {
        Section {
            // Principal — big field
            HStack {
                Text("Montant emprunté")
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
                    Text("Taux d'intérêt annuel")
                    Text("Taux nominal tel qu'inscrit au contrat")
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
            Text("Montant et taux")
        }
    }

    private var scheduleSection: some View {
        Section("Durée et versements") {
            // Term — years + months
            HStack {
                Text("Durée")
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

            Picker("Fréquence des versements", selection: $frequency) {
                ForEach(LoanPaymentFrequency.allCases) { f in
                    Text(f.labelFR).tag(f)
                }
            }

            DatePicker("Premier versement", selection: $firstPaymentDate, displayedComponents: .date)

            Button {
                withAnimation { showAdvanced.toggle() }
            } label: {
                HStack {
                    Text(showAdvanced ? "Masquer les options avancées" : "Options avancées")
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
                ForEach(LoanCompounding.allCases) { c in Text(c.labelFR).tag(c) }
            }
        } header: {
            Text("Avancé")
        } footer: {
            Text("Les hypothèques canadiennes utilisent la capitalisation semestrielle (Loi sur les intérêts). Les prêts personnels et auto utilisent généralement la capitalisation mensuelle.")
        }
    }

    private var accountSection: some View {
        Section("Compte débité") {
            if accounts.isEmpty {
                Text("Aucun compte. Créez-en un d'abord.")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Compte", selection: $selectedAccount) {
                    Text("Aucun (suivi seulement)").tag(Account?.none)
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
                summaryRow("Versement \(frequency.labelFR.lowercased())",
                           value: formatAmount(calc.paymentAmount),
                           highlight: true)

                if frequency == .biweeklyAccelerated {
                    let saved = calc.totalPayments - calc.effectivePayments
                    summaryRow("Versements économisés",
                               value: "\(saved) versements",
                               color: .green)
                }

                summaryRow("Total des intérêts",
                           value: formatAmount(calc.totalInterest),
                           color: calc.totalInterest > calc.principal ? .red : .primary)

                summaryRow("Coût total du prêt",
                           value: formatAmount(calc.totalAmountPaid))

                summaryRow("Date de fin estimée",
                           value: calc.payoffDate.formatted(date: .long, time: .omitted))
            } header: {
                Text("Résumé calculé")
            } footer: {
                Text("Calcul basé sur les informations saisies. Vérifiez votre contrat de prêt pour les conditions exactes.")
            }
        }
    }

    private var recurringSection: some View {
        Section {
            Toggle(isOn: $createRecurring) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Créer un versement récurrent")
                    Text("Enregistre automatiquement chaque paiement dans vos transactions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var notesSection: some View {
        Section("Notes (optionnel)") {
            TextField("Numéro de contrat, courtier, etc.", text: $notes, axis: .vertical)
                .lineLimit(2...4)
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) { showDeleteConfirm = true } label: {
                Label("Supprimer ce prêt", systemImage: "trash")
            }
        } footer: {
            Text("Supprime le prêt et son versement récurrent associé. Les transactions déjà enregistrées sont conservées.")
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
            context.insert(loan)

            // Auto-create recurring transaction if requested
            if createRecurring, let calc = calculator {
                let amount = Decimal(calc.paymentAmount)
                let rule = RecurringTransaction(
                    title: trimLabel.isEmpty ? type.labelFR : trimLabel,
                    amount: amount,
                    type: .expense,
                    frequency: frequency.recurringFrequency,
                    startDate: firstPaymentDate,
                    account: selectedAccount,
                    note: "Remboursement \(trimLender.isEmpty ? type.labelFR : trimLender)",
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
        }

        do {
            try context.save()
            dismiss()
        } catch {
            print("AddEditLoanView: save failed — \(error)")
        }
    }

    private func deleteIfEditing() {
        guard case .edit(let loan) = mode else { return }
        context.delete(loan)
        try? context.save()
        dismiss()
    }

    private func decimalToText(_ d: Decimal) -> String {
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal
        fmt.locale = Locale(identifier: "fr_CA")
        fmt.maximumFractionDigits = 2
        fmt.minimumFractionDigits = 0
        fmt.usesGroupingSeparator = false
        return fmt.string(from: NSDecimalNumber(decimal: d)) ?? "\(d)"
    }
}
