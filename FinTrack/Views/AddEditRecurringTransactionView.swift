//
//  AddEditRecurringTransactionView.swift
//  FinTrack
//

import SwiftUI
import SwiftData

enum RecurringEditorMode {
    case create
    case edit(RecurringTransaction)
}

struct AddEditRecurringTransactionView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let mode: RecurringEditorMode

    @Query(filter: #Predicate<Account> { !$0.isArchived },
           sort: \Account.createdAt, order: .forward)
    private var accounts: [Account]

    @Query(filter: #Predicate<Category> { !$0.isHidden },
           sort: \Category.name, order: .forward)
    private var categories: [Category]

    // Form state
    @State private var title: String = ""
    @State private var type: TransactionType = .expense
    @State private var amountText: String = ""
    @State private var frequency: RecurrenceFrequency = .monthly
    @State private var startDate: Date = Calendar.current.startOfDay(for: .now)
    @State private var hasEndDate: Bool = false
    @State private var endDate: Date = Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now
    @State private var selectedAccount: Account?
    @State private var selectedCategory: Category?
    @State private var payee: String = ""
    @State private var note: String = ""
    @State private var isActive: Bool = true
    @State private var showCategoryPicker = false
    @State private var showDeleteConfirm = false

    @FocusState private var amountFocused: Bool

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var navTitle: String {
        isEditing ? "Modifier la récurrence" : "Nouvelle récurrence"
    }

    private var currencyCode: String {
        selectedAccount?.currency ?? Currencies.default
    }

    private var canSave: Bool {
        guard let amount = parseAmount(), amount > 0 else { return false }
        return selectedAccount != nil
    }

    private var applicableCategories: [Category] {
        categories.filter { $0.matches(type) }
    }

    var body: some View {
        NavigationStack {
            Form {
                amountSection
                typeSection
                scheduleSection
                accountSection
                categorySection
                detailsSection
                if isEditing { statusSection }
                if isEditing { deleteSection }
            }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Enregistrer") { save() }
                        .disabled(!canSave)
                        .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showCategoryPicker) {
                CategoryPickerSheet(
                    type: type,
                    categories: applicableCategories,
                    selected: $selectedCategory
                )
            }
            .confirmationDialog("Supprimer cette récurrence ?",
                                isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Supprimer", role: .destructive) { deleteIfEditing() }
                Button("Annuler", role: .cancel) {}
            }
            .onAppear(perform: loadIfEditing)
        }
    }

    // MARK: - Sections

    private var amountSection: some View {
        Section {
            HStack(spacing: 6) {
                Text(type == .expense ? "−" : "+")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(type == .expense ? .red : .green)

                TextField("0", text: $amountText)
                    .font(.system(size: 44, weight: .light, design: .rounded))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .focused($amountFocused)
                    .frame(maxWidth: .infinity)

                Text(Currencies.info(for: currencyCode).symbol)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 50, alignment: .leading)
            }
            .padding(.vertical, 8)
        }
    }

    private var typeSection: some View {
        Section {
            Picker("Type", selection: $type) {
                Text("Dépense").tag(TransactionType.expense)
                Text("Revenu").tag(TransactionType.income)
            }
            .pickerStyle(.segmented)
            .onChange(of: type) { _, _ in
                if let cat = selectedCategory, !cat.matches(type) {
                    selectedCategory = nil
                }
            }
        }
    }

    private var scheduleSection: some View {
        Section("Planification") {
            // Label (optional but helpful for payroll, rent, etc.)
            TextField("Nom (ex. Salaire BNC, Loyer)", text: $title)

            Picker("Fréquence", selection: $frequency) {
                ForEach(RecurrenceFrequency.allCases) { f in
                    HStack {
                        Image(systemName: f.iconSystemName)
                        Text(f.labelFR)
                    }
                    .tag(f)
                }
            }

            DatePicker("Première occurrence", selection: $startDate, displayedComponents: .date)

            Toggle("Date de fin", isOn: $hasEndDate.animation())
            if hasEndDate {
                DatePicker("Fin le", selection: $endDate,
                           in: startDate..., displayedComponents: .date)
            }
        }
    }

    private var accountSection: some View {
        Section("Compte") {
            if accounts.isEmpty {
                Text("Aucun compte. Créez-en un d'abord.")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Compte", selection: $selectedAccount) {
                    Text("Choisir…").tag(Account?.none)
                    ForEach(accounts) { account in
                        HStack {
                            Image(systemName: account.iconSystemName)
                                .foregroundStyle(Color(hex: account.colorHex))
                            Text(account.name)
                            Text("(\(account.currency))")
                                .foregroundStyle(.secondary)
                        }
                        .tag(Optional(account))
                    }
                }
            }
        }
    }

    private var categorySection: some View {
        Section("Catégorie") {
            Button {
                showCategoryPicker = true
            } label: {
                HStack {
                    if let cat = selectedCategory {
                        ZStack {
                            Circle()
                                .fill(Color(hex: cat.colorHex).opacity(0.2))
                                .frame(width: 28, height: 28)
                            Image(systemName: cat.iconSystemName)
                                .font(.caption)
                                .foregroundStyle(Color(hex: cat.colorHex))
                        }
                        Text(cat.name).foregroundStyle(.primary)
                    } else {
                        Image(systemName: "tag").foregroundStyle(.secondary)
                        Text("Aucune catégorie").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var detailsSection: some View {
        Section("Détails") {
            TextField(type == .income ? "Source (employeur, client…)"
                                       : "Bénéficiaire (commerce, abonnement…)",
                      text: $payee)
            TextField("Note", text: $note, axis: .vertical)
                .lineLimit(1...3)
        }
    }

    private var statusSection: some View {
        Section {
            Toggle(isActive ? "Récurrence active" : "Récurrence en pause",
                   isOn: $isActive)
        } footer: {
            Text(isActive
                 ? "Les transactions seront générées automatiquement aux échéances."
                 : "La génération est suspendue. Aucune transaction ne sera créée jusqu'à la réactivation.")
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("Supprimer cette récurrence", systemImage: "trash")
            }
        } footer: {
            Text("Supprime la règle uniquement. Les transactions déjà enregistrées sont conservées.")
        }
    }

    // MARK: - Logic

    private func loadIfEditing() {
        guard case .edit(let rule) = mode else {
            // Create mode: default account
            selectedAccount = accounts.first
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                amountFocused = true
            }
            return
        }
        title = rule.title
        type = rule.type
        amountText = decimalToText(rule.amount)
        frequency = rule.frequency
        startDate = rule.startDate
        if let end = rule.endDate {
            hasEndDate = true
            endDate = end
        }
        selectedAccount = rule.account
        selectedCategory = rule.category
        payee = rule.payee ?? ""
        note = rule.note
        isActive = rule.isActive
    }

    private func save() {
        guard let amount = parseAmount(), amount > 0,
              let account = selectedAccount else { return }

        let trimmedTitle  = title.trimmingCharacters(in: .whitespaces)
        let trimmedPayee  = payee.trimmingCharacters(in: .whitespaces)
        let trimmedNote   = note.trimmingCharacters(in: .whitespaces)

        switch mode {
        case .create:
            let rule = RecurringTransaction(
                title: trimmedTitle,
                amount: amount,
                type: type,
                frequency: frequency,
                startDate: startDate,
                endDate: hasEndDate ? endDate : nil,
                account: account,
                category: selectedCategory,
                note: trimmedNote,
                payee: trimmedPayee.isEmpty ? nil : trimmedPayee
            )
            context.insert(rule)
            // Immediately apply if the start date is today or earlier.
            RecurringTransactionManager.applyPending(context: context)

        case .edit(let rule):
            rule.title = trimmedTitle
            rule.amount = amount
            rule.type = type
            rule.frequency = frequency
            rule.startDate = startDate
            rule.endDate = hasEndDate ? endDate : nil
            rule.account = account
            rule.category = selectedCategory
            rule.note = trimmedNote
            rule.payee = trimmedPayee.isEmpty ? nil : trimmedPayee
            rule.isActive = isActive
        }

        do {
            try context.save()
            dismiss()
        } catch {
            print("AddEditRecurringTransactionView: save failed — \(error)")
        }
    }

    private func deleteIfEditing() {
        guard case .edit(let rule) = mode else { return }
        context.delete(rule)
        try? context.save()
        dismiss()
    }

    private func parseAmount() -> Decimal? {
        let normalized = amountText
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        guard !normalized.isEmpty else { return nil }
        return Decimal(string: normalized)
    }

    private func decimalToText(_ d: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "fr_CA")
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSDecimalNumber(decimal: d)) ?? "\(d)"
    }
}

// MARK: - Category picker (reuse logic, local copy to avoid cross-file private)

private struct CategoryPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let type: TransactionType
    let categories: [Category]
    @Binding var selected: Category?
    private let columns = [GridItem(.adaptive(minimum: 90), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    tile(name: "Aucune", icon: "circle.dashed", color: .gray, isSelected: selected == nil) {
                        selected = nil; dismiss()
                    }
                    ForEach(categories) { cat in
                        tile(name: cat.name, icon: cat.iconSystemName,
                             color: Color(hex: cat.colorHex), isSelected: selected?.id == cat.id) {
                            selected = cat; dismiss()
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Catégorie")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Fermer") { dismiss() } }
            }
        }
    }

    private func tile(name: String, icon: String, color: Color, isSelected: Bool,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle().fill(isSelected ? color : color.opacity(0.15)).frame(width: 52, height: 52)
                    Image(systemName: icon).font(.title3).foregroundStyle(isSelected ? .white : color)
                }
                Text(name).font(.caption).foregroundStyle(.primary)
                    .multilineTextAlignment(.center).lineLimit(2).frame(height: 30)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? color : Color(.separator), lineWidth: isSelected ? 2 : 0.5))
        }
        .buttonStyle(.plain)
    }
}
