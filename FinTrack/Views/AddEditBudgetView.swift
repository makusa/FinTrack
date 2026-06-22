//
//  AddEditBudgetView.swift
//  FinTrack
//

import SwiftUI
import SwiftData

enum BudgetEditorMode {
    case create
    case edit(Budget)
}

struct AddEditBudgetView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss)      private var dismiss
    @Environment(LanguageManager.self) private var lang
    @Environment(ExchangeRateManager.self) private var rates

    let mode: BudgetEditorMode

    /// Currencies offered in the picker: the user's tracked list, plus this
    /// item's own currency if it's no longer tracked (so it's never lost).
    private var pickerCurrencies: [CurrencyInfo] {
        var list = rates.activeCurrencyInfos
        if !list.contains(where: { $0.code == currency }) {
            list.append(Currencies.info(for: currency))
        }
        return list
    }

    // MARK: Queries

    @Query(filter: #Predicate<Category> { !$0.isHidden && ($0.applicabilityRaw == "expense" || $0.applicabilityRaw == "both") },
           sort: \Category.name)
    private var expenseCategories: [Category]

    @Query(filter: #Predicate<Account> { !$0.isArchived }, sort: \Account.createdAt)
    private var accounts: [Account]

    // MARK: Form state

    @State private var name: String = ""
    @State private var limitText: String = ""
    @State private var currency: String = Currencies.default
    @State private var period: BudgetPeriod = .monthly
    @State private var selectedCategoryID: PersistentIdentifier? = nil   // nil = global (toutes catégories)
    @State private var colorHex: String = ColorPalette.accountColors.first ?? "#3478F6"
    @State private var iconSystemName: String = "cart.fill"
    @State private var notes: String = ""
    @State private var showDeleteConfirm = false

    @FocusState private var limitFocused: Bool

    private var isEditing: Bool { if case .edit = mode { return true } ; return false }

    private var selectedCategoryObject: Category? {
        expenseCategories.first { $0.persistentModelID == selectedCategoryID }
    }

    private var limit: Decimal? {
        Decimal(string: limitText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && (limit ?? 0) > 0
    }

    private let iconChoices = [
        "cart.fill", "fork.knife", "car.fill", "house.fill", "bolt.fill",
        "cross.case.fill", "film.fill", "tshirt.fill", "book.fill", "airplane",
        "gift.fill", "building.columns", "doc.text.fill", "globe", "briefcase.fill",
        "star.fill", "heart.fill", "leaf.fill", "tag.fill", "creditcard.fill",
        "bag.fill", "wifi", "phone.fill", "gamecontroller.fill", "music.note",
    ]

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Limit amount (big)
                Section {
                    HStack(spacing: 8) {
                        TextField("0", text: $limitText)
                            .font(.system(size: 42, weight: .light, design: .rounded))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.center)
                            .focused($limitFocused)
                        Text(Currencies.info(for: currency).symbol)
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                    Picker(lang["label.currency"], selection: $currency) {
                        ForEach(pickerCurrencies) { c in
                            Text("\(c.code) — \(c.name)").tag(c.code)
                        }
                    }
                } header: {
                    Text(lang["budget.limit"])
                }

                // MARK: Identification
                Section(lang["label.information"]) {
                    TextField(lang["budget.name.placeholder"], text: $name)
                    Picker(lang["budget.period"], selection: $period) {
                        ForEach(BudgetPeriod.allCases) { p in
                            Text(p.label).tag(p)
                        }
                    }
                }

                // MARK: Category — sélection via une liste explicite (NavigationLink).
                // Un Picker .navigationLink ne permettait pas de changer la catégorie
                // quand elle était déjà remplie (édition). Des boutons explicites qui
                // écrivent la sélection puis ferment sont fiables dans tous les cas.
                Section {
                    NavigationLink {
                        BudgetCategoryPickerList(
                            categories: expenseCategories,
                            allLabel: lang["budget.category.all"],
                            selectedID: $selectedCategoryID
                        )
                        .navigationTitle(lang["label.category"])
                        .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        HStack {
                            Text(lang["label.category"])
                            Spacer()
                            if let cat = selectedCategoryObject {
                                Image(systemName: cat.iconSystemName)
                                    .foregroundStyle(Color(hex: cat.colorHex))
                                Text(cat.localizedName)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(lang["budget.category.all"])
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text(lang["label.category"])
                } footer: {
                    Text(lang["budget.category.footer"])
                }

                // MARK: Appearance
                Section(lang["label.appearance"]) {
                    colorPicker
                    iconPicker
                }

                // MARK: Notes
                Section(lang["label.notes"] + " " + lang["label.optional"]) {
                    TextField(lang["label.note"], text: $notes, axis: .vertical)
                        .lineLimit(1...3)
                }

                // MARK: Delete
                if isEditing {
                    Section {
                        Button(role: .destructive) { showDeleteConfirm = true } label: {
                            Label(lang["budget.delete"], systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? lang["budget.edit"] : lang["budget.create"])
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading)  { Button(lang["action.cancel"]) { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(lang["action.save"]) { save() }
                        .disabled(!canSave)
                        .fontWeight(.semibold)
                }
            }
            .confirmationDialog(lang["budget.delete"], isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button(lang["action.delete"], role: .destructive) { deleteIfEditing() }
                Button(lang["action.cancel"], role: .cancel) {}
            }
            .onAppear {
                loadIfEditing()
                if !isEditing {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { limitFocused = true }
                }
            }
        }
    }

    // MARK: - Sub-views

    private var colorPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(lang["label.color"]).font(.subheadline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(ColorPalette.accountColors, id: \.self) { hex in
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 32, height: 32)
                            .overlay {
                                if hex == colorHex {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.white)
                                        .font(.system(size: 14, weight: .bold))
                                }
                            }
                            .onTapGesture { colorHex = hex }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var iconPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(lang["label.icon"]).font(.subheadline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(iconChoices, id: \.self) { icon in
                        Image(systemName: icon)
                            .font(.system(size: 18))
                            .frame(width: 40, height: 40)
                            .background(
                                icon == iconSystemName
                                    ? Color(hex: colorHex)
                                    : Color(.tertiarySystemBackground),
                                in: Circle()
                            )
                            .foregroundStyle(icon == iconSystemName ? .white : .primary)
                            .onTapGesture { iconSystemName = icon }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Logic

    private func loadIfEditing() {
        guard case .edit(let b) = mode else { return }
        name             = b.name
        limitText        = decimalToText(b.limitAmount)
        currency         = b.currency
        period           = b.period
        selectedCategoryID = b.category?.persistentModelID
        colorHex         = b.colorHex
        iconSystemName   = b.iconSystemName
        notes            = b.notes ?? ""
    }

    private func save() {
        guard let amt = limit, amt > 0 else { return }
        let trimmedName  = name.trimmingCharacters(in: .whitespaces)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespaces)
        let chosenCategory = expenseCategories.first { $0.persistentModelID == selectedCategoryID }

        switch mode {
        case .create:
            let b = Budget(
                name: trimmedName,
                limitAmount: amt,
                currency: currency,
                period: period,
                colorHex: colorHex,
                iconSystemName: iconSystemName,
                category: chosenCategory,
                notes: trimmedNotes.isEmpty ? nil : trimmedNotes
            )
            context.insert(b)
        case .edit(let b):
            b.name           = trimmedName
            b.limitAmount    = amt
            b.currency       = currency
            b.period         = period
            b.colorHex       = colorHex
            b.iconSystemName = iconSystemName
            b.category       = chosenCategory
            b.notes          = trimmedNotes.isEmpty ? nil : trimmedNotes
        }
        try? context.save()
        dismiss()
    }

    private func deleteIfEditing() {
        guard case .edit(let b) = mode else { return }
        context.delete(b)
        try? context.save()
        dismiss()
    }

    private func decimalToText(_ d: Decimal) -> String {
        return d.appFormattedForInput
    }
}

// MARK: - Sélecteur de catégorie (liste explicite, fiable en création comme en édition)

private struct BudgetCategoryPickerList: View {
    @Environment(\.dismiss) private var dismiss

    let categories: [Category]
    let allLabel: String
    @Binding var selectedID: PersistentIdentifier?

    var body: some View {
        List {
            Button {
                selectedID = nil
                dismiss()
            } label: {
                HStack {
                    Image(systemName: "square.grid.2x2")
                        .foregroundStyle(.secondary)
                    Text(allLabel)
                        .foregroundStyle(.primary)
                    Spacer()
                    if selectedID == nil {
                        Image(systemName: "checkmark").foregroundStyle(.tint)
                    }
                }
            }
            ForEach(categories) { cat in
                Button {
                    selectedID = cat.persistentModelID
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: cat.iconSystemName)
                            .foregroundStyle(Color(hex: cat.colorHex))
                        Text(cat.localizedName)
                            .foregroundStyle(.primary)
                        Spacer()
                        if selectedID == cat.persistentModelID {
                            Image(systemName: "checkmark").foregroundStyle(.tint)
                        }
                    }
                }
            }
        }
    }
}
