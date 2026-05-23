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

    let mode: BudgetEditorMode

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
    @State private var selectedCategory: Category? = nil   // nil = global
    @State private var colorHex: String = ColorPalette.accountColors.first ?? "#3478F6"
    @State private var iconSystemName: String = "cart.fill"
    @State private var notes: String = ""
    @State private var showDeleteConfirm = false

    @FocusState private var limitFocused: Bool

    private var isEditing: Bool { if case .edit = mode { return true } ; return false }

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
                        ForEach(Currencies.all) { c in
                            Text("\(c.code) — \(c.nameFR)").tag(c.code)
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

                // MARK: Category
                Section {
                    Picker(lang["label.category"], selection: $selectedCategory) {
                        Text(lang["budget.category.all"]).tag(Category?.none)
                        ForEach(expenseCategories) { cat in
                            HStack {
                                Image(systemName: cat.iconSystemName)
                                    .foregroundStyle(Color(hex: cat.colorHex))
                                Text(cat.name)
                            }
                            .tag(Optional(cat))
                        }
                    }
                    .pickerStyle(.navigationLink)
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
        selectedCategory = b.category
        colorHex         = b.colorHex
        iconSystemName   = b.iconSystemName
        notes            = b.notes ?? ""
    }

    private func save() {
        guard let amt = limit, amt > 0 else { return }
        let trimmedName  = name.trimmingCharacters(in: .whitespaces)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespaces)

        switch mode {
        case .create:
            let b = Budget(
                name: trimmedName,
                limitAmount: amt,
                currency: currency,
                period: period,
                colorHex: colorHex,
                iconSystemName: iconSystemName,
                category: selectedCategory,
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
            b.category       = selectedCategory
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
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "fr_CA")
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 0
        f.usesGroupingSeparator = false
        return f.string(from: NSDecimalNumber(decimal: d)) ?? "\(d)"
    }
}
