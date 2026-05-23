//
//  AddEditTransactionView.swift
//  FinTrack
//

import SwiftUI
import SwiftData

enum TransactionEditorMode {
    case create
    case edit(Transaction)
}

struct AddEditTransactionView: View {
    @Environment(\.modelContext) private var context
    @Environment(LanguageManager.self) private var lang
    @Environment(\.dismiss) private var dismiss

    let mode: TransactionEditorMode
    let preselectedAccount: Account?

    @Query(filter: #Predicate<Account> { !$0.isArchived },
           sort: \Account.createdAt, order: .forward)
    private var accounts: [Account]

    @Query(filter: #Predicate<Category> { !$0.isHidden },
           sort: \Category.name, order: .forward)
    private var categories: [Category]

    @State private var type: TransactionType = .expense
    @State private var amountText: String = ""
    @State private var selectedAccount: Account?
    @State private var selectedCategory: Category?
    @State private var date: Date = .now
    @State private var payee: String = ""
    @State private var note: String = ""
    @State private var showCategoryPicker = false
    @State private var showDeleteConfirm = false

    @FocusState private var amountFocused: Bool

    init(mode: TransactionEditorMode, preselectedAccount: Account? = nil) {
        self.mode = mode
        self.preselectedAccount = preselectedAccount
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var navTitle: String {
        isEditing ? lang["tx.edit"] : lang["tx.create"]
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
        // No internal NavigationStack: callers wrap as needed (sheet vs push).
        Form {
            amountSection
            typeSection
            accountSection
            categorySection
            detailsSection

            if case .edit = mode {
                Section {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label(lang["action.delete"], systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle(navTitle)
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
        .sheet(isPresented: $showCategoryPicker) {
            CategoryPickerSheet(
                type: type,
                categories: applicableCategories,
                selected: $selectedCategory
            )
        }
        .confirmationDialog(lang["tx.deletePrompt"],
                            isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button(lang["action.delete"], role: .destructive) { deleteIfEditing() }
            Button(lang["action.cancel"], role: .cancel) {}
        }
        .onAppear(perform: setupInitialValues)
    }

    // MARK: - Sections

    private var amountSection: some View {
        Section {
            HStack(spacing: 6) {
                Text(type == .expense ? "−" : "+")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(type == .expense ? Color.red : Color.green)

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
                Text(lang["tx.type.expense"]).tag(TransactionType.expense)
                Text(lang["tx.type.income"]).tag(TransactionType.income)
            }
            .pickerStyle(.segmented)
            .onChange(of: type) { _, _ in
                // Clear the category if it no longer fits the new type.
                if let cat = selectedCategory, !cat.matches(type) {
                    selectedCategory = nil
                }
            }
        }
    }

    private var accountSection: some View {
        Section(lang["label.account"]) {
            if accounts.isEmpty {
                Text(lang["label.account"])
                    .foregroundStyle(.secondary)
            } else {
                Picker(lang["label.account"], selection: $selectedAccount) {
                    Text(lang["label.none"] + "…").tag(Account?.none)
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
        Section(lang["label.category"]) {
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
                        Text(cat.name)
                            .foregroundStyle(.primary)
                    } else {
                        Image(systemName: "tag")
                            .foregroundStyle(.secondary)
                        Text(lang["tx.noCategory"])
                            .foregroundStyle(.secondary)
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
        Section(lang["label.details"]) {
            DatePicker(lang["label.date"], selection: $date, displayedComponents: .date)
            TextField(type == .income ? lang["tx.payeeIncome"]
                                       : lang["tx.payeeExpense"],
                      text: $payee)
            TextField(lang["label.note"], text: $note, axis: .vertical)
                .lineLimit(1...3)
        }
    }

    // MARK: - Logic

    private func setupInitialValues() {
        switch mode {
        case .create:
            if let preselected = preselectedAccount {
                selectedAccount = preselected
            } else {
                selectedAccount = accounts.first
            }
            // Open the keyboard immediately so Régis can start typing the amount.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                amountFocused = true
            }
        case .edit(let tx):
            type = tx.type
            amountText = decimalToText(tx.amount)
            selectedAccount = tx.account
            selectedCategory = tx.category
            date = tx.date
            payee = tx.payee ?? ""
            note = tx.note
        }
    }

    private func save() {
        guard let amount = parseAmount(), amount > 0,
              let account = selectedAccount else { return }

        let trimmedPayee = payee.trimmingCharacters(in: .whitespaces)
        let trimmedNote = note.trimmingCharacters(in: .whitespaces)

        switch mode {
        case .create:
            let tx = Transaction(
                amount: amount,
                type: type,
                date: date,
                account: account,
                category: selectedCategory,
                note: trimmedNote,
                payee: trimmedPayee.isEmpty ? nil : trimmedPayee
            )
            context.insert(tx)
        case .edit(let tx):
            tx.amount = amount
            tx.type = type
            tx.date = date
            tx.account = account
            tx.category = selectedCategory
            tx.note = trimmedNote
            tx.payee = trimmedPayee.isEmpty ? nil : trimmedPayee
        }

        do {
            try context.save()
            dismiss()
        } catch {
            print("AddEditTransactionView: save failed — \(error)")
        }
    }

    private func deleteIfEditing() {
        guard case .edit(let tx) = mode else { return }
        context.delete(tx)
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

// MARK: - Category picker sheet

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
                    // "None" option
                    categoryTile(
                        name: "Aucune",
                        icon: "circle.dashed",
                        color: .gray,
                        isSelected: selected == nil
                    ) {
                        selected = nil
                        dismiss()
                    }

                    ForEach(categories) { cat in
                        categoryTile(
                            name: cat.name,
                            icon: cat.iconSystemName,
                            color: Color(hex: cat.colorHex),
                            isSelected: selected?.id == cat.id
                        ) {
                            selected = cat
                            dismiss()
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Catégorie")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(LanguageManager.shared["action.close"]) { dismiss() }
                }
            }
        }
    }

    private func categoryTile(name: String, icon: String, color: Color,
                              isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(isSelected ? color : color.opacity(0.15))
                        .frame(width: 52, height: 52)
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundStyle(isSelected ? .white : color)
                }
                Text(name)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(height: 30)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? color : Color(.separator), lineWidth: isSelected ? 2 : 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}
