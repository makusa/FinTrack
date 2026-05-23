//
//  AddEditCreditLineView.swift
//  FinTrack
//

import SwiftUI
import SwiftData

enum CreditLineEditorMode {
    case create
    case edit(CreditLine)
}

struct AddEditCreditLineView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss)      private var dismiss

    let mode: CreditLineEditorMode

    @Query(filter: #Predicate<Account> { !$0.isArchived },
           sort: \Account.createdAt, order: .forward)
    private var accounts: [Account]

    // MARK: Form state
    @State private var name                 = ""
    @State private var lenderName           = ""
    @State private var currency             = Currencies.default
    @State private var limitText            = ""
    @State private var rateText             = ""
    @State private var compounding          = CreditLineCompounding.daily
    @State private var minPayType           = MinimumPaymentType.interestOnly
    @State private var minPayValueText      = ""
    @State private var selectedAccount: Account? = nil
    @State private var notes                = ""
    @State private var currentDrawText      = ""   // only for .create: pre-fill initial draw
    @State private var createRecurring      = false
    @State private var recurringAmountText  = ""
    @State private var recurringFrequency   = RecurrenceFrequency.monthly
    @State private var showDeleteConfirm    = false
    @State private var showAdvanced         = false

    @FocusState private var limitFocused: Bool

    private var isEditing: Bool { if case .edit = mode { return true }; return false }
    private var navTitle: String { isEditing ? "Modifier la marge" : "Nouvelle marge de crédit" }

    private var limit: Decimal? { parseDecimal(limitText) }
    private var rate:  Decimal? { parseDecimal(rateText) }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && limit != nil && rate != nil
    }

    // MARK: Live estimates
    private var estimatedMonthlyInterest: Decimal? {
        guard let lim = limit, let r = rate else { return nil }
        let drawAmt = parseDecimal(currentDrawText) ?? 0
        let bal = isEditing ? (mode == .create ? drawAmt : Decimal(0)) : drawAmt
        guard (bal as NSDecimalNumber).doubleValue > 0 else { return nil }
        return bal * r / 100 / 12
    }

    var body: some View {
        NavigationStack {
            Form {
                identitySection
                financialSection
                if showAdvanced { advancedSection }
                if !isEditing   { initialDrawSection }
                minPaymentSection
                accountSection
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
                        .disabled(!canSave).fontWeight(.semibold)
                }
            }
            .confirmationDialog("Supprimer cette marge ?",
                                isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Supprimer", role: .destructive) { deleteIfEditing() }
                Button("Annuler", role: .cancel) {}
            }
            .onAppear(perform: loadIfEditing)
        }
    }

    // MARK: - Sections

    private var identitySection: some View {
        Section("Identification") {
            TextField("Nom (ex. Marge BNC, HELOC Desjardins)", text: $name)
            TextField("Prêteur (ex. Banque Nationale)", text: $lenderName)
            Picker("Devise", selection: $currency) {
                ForEach(Currencies.all) { c in Text("\(c.code) — \(c.nameFR)").tag(c.code) }
            }
        }
    }

    private var financialSection: some View {
        Section {
            HStack {
                Text("Plafond autorisé")
                Spacer()
                TextField("0", text: $limitText)
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    .focused($limitFocused).frame(maxWidth: 150)
                Text(Currencies.info(for: currency).symbol).foregroundStyle(.secondary)
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Taux d'intérêt annuel")
                    Text("Tel qu'indiqué dans votre contrat")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                TextField("0,00", text: $rateText)
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(maxWidth: 70)
                Text("%").foregroundStyle(.secondary)
            }

            Button {
                withAnimation { showAdvanced.toggle() }
            } label: {
                HStack {
                    Text(showAdvanced ? "Masquer options avancées" : "Options avancées")
                        .font(.callout)
                    Spacer()
                    Image(systemName: showAdvanced ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        } header: {
            Text("Montant et taux")
        }
    }

    private var advancedSection: some View {
        Section {
            Picker("Capitalisation", selection: $compounding) {
                ForEach(CreditLineCompounding.allCases) { c in Text(c.labelFR).tag(c) }
            }
        } header: { Text("Avancé") } footer: {
            Text("La plupart des marges de crédit canadiennes utilisent la capitalisation quotidienne.")
        }
    }

    private var initialDrawSection: some View {
        Section {
            HStack {
                Text("Solde actuel utilisé")
                Spacer()
                TextField("0", text: $currentDrawText)
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(maxWidth: 150)
                Text(Currencies.info(for: currency).symbol).foregroundStyle(.secondary)
            }
            if let est = estimatedMonthlyInterest, (est as NSDecimalNumber).doubleValue > 0 {
                HStack {
                    Text("Intérêts mensuels estimés").foregroundStyle(.secondary)
                    Spacer()
                    Text("≈ \(est.formatted(asCurrency: currency))")
                        .foregroundStyle(.orange).fontWeight(.medium)
                }
            }
        } header: { Text("Solde initial") } footer: {
            Text("Entrez le montant actuellement utilisé sur cette marge. Vous pourrez ensuite ajouter des retraits et remboursements manuellement.")
        }
    }

    private var minPaymentSection: some View {
        Section {
            Picker("Type de paiement minimum", selection: $minPayType) {
                ForEach(MinimumPaymentType.allCases) { t in Text(t.labelFR).tag(t) }
            }
            if minPayType == .percentBalance || minPayType == .fixedAmount {
                HStack {
                    Text(minPayType == .percentBalance ? "Pourcentage du solde" : "Montant fixe")
                    Spacer()
                    TextField("0", text: $minPayValueText)
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(maxWidth: 100)
                    Text(minPayType == .percentBalance ? "%" : Currencies.info(for: currency).symbol)
                        .foregroundStyle(.secondary)
                }
            }
        } header: { Text("Paiement minimum") } footer: {
            Text("Utilisé pour estimer l'obligation mensuelle dans le flux de trésorerie.")
        }
    }

    private var accountSection: some View {
        Section("Compte associé (optionnel)") {
            Picker("Compte", selection: $selectedAccount) {
                Text("Aucun").tag(Account?.none)
                ForEach(accounts) { acc in
                    HStack {
                        Image(systemName: acc.iconSystemName).foregroundStyle(Color(hex: acc.colorHex))
                        Text(acc.name)
                    }.tag(Optional(acc))
                }
            }
        }
    }

    private var recurringSection: some View {
        Section {
            Toggle(isOn: $createRecurring.animation()) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Remboursement récurrent")
                    Text("Enregistre automatiquement un paiement périodique")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if createRecurring {
                HStack {
                    Text("Montant")
                    Spacer()
                    TextField("0", text: $recurringAmountText)
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(maxWidth: 120)
                    Text(Currencies.info(for: currency).symbol).foregroundStyle(.secondary)
                }
                Picker("Fréquence", selection: $recurringFrequency) {
                    ForEach(RecurrenceFrequency.allCases) { f in Text(f.labelFR).tag(f) }
                }
            }
        } header: { Text("Remboursement automatique") }
    }

    private var notesSection: some View {
        Section("Notes (optionnel)") {
            TextField("Numéro de compte, conditions, etc.", text: $notes, axis: .vertical)
                .lineLimit(2...4)
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) { showDeleteConfirm = true } label: {
                Label("Supprimer cette marge", systemImage: "trash")
            }
        } footer: {
            Text("Supprime la marge et tout son historique de mouvements.")
        }
    }

    // MARK: - Logic

    private func loadIfEditing() {
        guard case .edit(let cl) = mode else {
            selectedAccount = accounts.first
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { limitFocused = true }
            return
        }
        name            = cl.name
        lenderName      = cl.lenderName
        currency        = cl.currency
        limitText       = decimalToText(cl.creditLimit)
        rateText        = decimalToText(cl.annualInterestRate)
        compounding     = cl.compounding
        minPayType      = cl.minimumPaymentType
        minPayValueText = (cl.minimumPaymentValue as NSDecimalNumber).doubleValue > 0
                          ? decimalToText(cl.minimumPaymentValue) : ""
        selectedAccount = cl.account
        notes           = cl.notes ?? ""
    }

    private func save() {
        guard let lim = limit, let r = rate else { return }
        let minVal = parseDecimal(minPayValueText) ?? 0
        let trimName   = name.trimmingCharacters(in: .whitespaces)
        let trimLender = lenderName.trimmingCharacters(in: .whitespaces)
        let trimNotes  = notes.trimmingCharacters(in: .whitespaces)

        switch mode {
        case .create:
            let cl = CreditLine(
                name: trimName, lenderName: trimLender, currency: currency,
                creditLimit: lim, annualInterestRate: r,
                compounding: compounding,
                minimumPaymentType: minPayType, minimumPaymentValue: minVal,
                account: selectedAccount,
                notes: trimNotes.isEmpty ? nil : trimNotes
            )
            context.insert(cl)

            // Initial draw entry
            if let drawAmt = parseDecimal(currentDrawText), drawAmt > 0 {
                let entry = CreditLineEntry(type: .draw, amount: drawAmt,
                                            date: .now, note: "Solde initial")
                entry.creditLine = cl
                context.insert(entry)
            }

            // Recurring repayment
            if createRecurring, let recAmt = parseDecimal(recurringAmountText), recAmt > 0 {
                let rule = RecurringTransaction(
                    title: trimName.isEmpty ? "Marge de crédit" : trimName,
                    amount: recAmt, type: .expense,
                    frequency: recurringFrequency,
                    startDate: Calendar.current.date(byAdding: .month, value: 1, to: .now) ?? .now,
                    account: selectedAccount,
                    note: "Remboursement \(trimLender.isEmpty ? "marge de crédit" : trimLender)",
                    payee: trimLender.isEmpty ? nil : trimLender,
                    isCreditLinePayment: true
                )
                context.insert(rule)
            }

        case .edit(let cl):
            cl.name                 = trimName
            cl.lenderName           = trimLender
            cl.currency             = currency
            cl.creditLimit          = lim
            cl.annualInterestRate   = r
            cl.compounding          = compounding
            cl.minimumPaymentType   = minPayType
            cl.minimumPaymentValue  = minVal
            cl.account              = selectedAccount
            cl.notes                = trimNotes.isEmpty ? nil : trimNotes
        }

        try? context.save()
        dismiss()
    }

    private func deleteIfEditing() {
        guard case .edit(let cl) = mode else { return }
        context.delete(cl); try? context.save(); dismiss()
    }

    private func parseDecimal(_ s: String) -> Decimal? {
        let n = s.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return nil }
        return Decimal(string: n)
    }

    private func decimalToText(_ d: Decimal) -> String {
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal; fmt.locale = Locale(identifier: "fr_CA")
        fmt.maximumFractionDigits = 2; fmt.minimumFractionDigits = 0
        fmt.usesGroupingSeparator = false
        return fmt.string(from: NSDecimalNumber(decimal: d)) ?? "\(d)"
    }
}
