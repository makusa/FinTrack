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
    @Environment(LanguageManager.self) private var lang
    @Environment(\.dismiss) private var dismiss

    let mode: RecurringEditorMode

    @Query(filter: #Predicate<Account> { !$0.isArchived },
           sort: \Account.createdAt, order: .forward)
    private var accounts: [Account]

    @Query(filter: #Predicate<Category> { !$0.isHidden },
           sort: \Category.name, order: .forward)
    private var categories: [Category]
    
    // Constants
    private let notificationDaysOptions = [1, 2, 3, 5, 7]

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
    @State private var isTransfer: Bool = false
    @State private var destinationAccount: Account? = nil
    @State private var showCategoryPicker = false
    @State private var showDeleteConfirm = false

    @State private var notifEnabled: Bool = false
    @State private var notifDaysBefore: Int = 3

    @FocusState private var amountFocused: Bool

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var navTitle: String {
        isEditing ? lang["recurring.edit"] : lang["recurring.create"]
    }

    private var currencyCode: String {
        selectedAccount?.currency ?? Currencies.default
    }

    private var canSave: Bool {
        guard let amount = parsedAmount, amount > 0 else { return false }
        guard selectedAccount != nil else { return false }
        // Transfers require a destination account
        if isTransfer && destinationAccount == nil { return false }
        return true
    }

    private var applicableCategories: [Category] {
        categories.filter { $0.matches(type) }
    }
    
    // Memoized amount parsing to avoid repeated calculations
    private var parsedAmount: Decimal? {
        let normalized = amountText
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        guard !normalized.isEmpty else { return nil }
        return Decimal(string: normalized)
    }
    
    // Reusable number formatter (created once)
    // Note: decimalFormatter is no longer static — locale may change at runtime.
    private var decimalFormatter: NumberFormatter {
        FormatterCache.decimal(locale: LanguageManager.shared.locale)
    }
    private static let _unused: Int = {
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        formatter.usesGroupingSeparator = false
        return formatter
    }()

    var body: some View {
        NavigationStack {
            Form {
                amountSection
                typeSection
                scheduleSection
                accountSection
                if isTransfer {
                    transferDestinationSection
                } else {
                    categorySection
                }
                detailsSection
                if isEditing { statusSection }
                notificationSection
                if isEditing { deleteSection }
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
            .confirmationDialog(lang["recurring.deletePrompt"],
                                isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button(lang["action.delete"], role: .destructive) { deleteIfEditing() }
                Button(lang["action.cancel"], role: .cancel) {}
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
            // Transfer toggle — when enabled, hides income/expense picker
            Toggle(lang["transfer.recurring.toggle"], isOn: $isTransfer)
                .onChange(of: isTransfer) { _, newValue in
                    // Clear destination when toggling off transfer mode
                    if !newValue {
                        destinationAccount = nil
                    }
                }

            if !isTransfer {
                Picker(lang["label.type"], selection: $type) {
                    Text(lang["tx.type.expense"]).tag(TransactionType.expense)
                    Text(lang["tx.type.income"]).tag(TransactionType.income)
                }
                .pickerStyle(.segmented)
                .onChange(of: type) { _, _ in
                    // Clear category if it doesn't match new type
                    if let cat = selectedCategory, !cat.matches(type) {
                        selectedCategory = nil
                    }
                }
            }
        }
    }

    private var scheduleSection: some View {
        Section(lang["recurring.schedule"]) {
            // Label (optional but helpful for payroll, rent, etc.)
            TextField(lang["recurring.name"], text: $title)

            Picker(lang["label.frequency"], selection: $frequency) {
                ForEach(RecurrenceFrequency.allCases) { f in
                    Label {
                        Text(f.label)
                    } icon: {
                        Image(systemName: f.iconSystemName)
                    }
                    .tag(f)
                }
            }

            DatePicker(lang["recurring.firstOccurrence"], 
                      selection: $startDate, 
                      displayedComponents: .date)

            Toggle(lang["recurring.endDate"], isOn: $hasEndDate)
            
            if hasEndDate {
                DatePicker(lang["recurring.endDate"], 
                          selection: $endDate,
                          in: startDate..., 
                          displayedComponents: .date)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: hasEndDate)
    }

    private var accountSection: some View {
        Section(lang["label.account"]) {
            if accounts.isEmpty {
                Text(lang["loan.noAccount"])
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
                .onChange(of: selectedAccount) { _, newAccount in
                    // Clear destination if it's the same as newly selected account
                    if let dest = destinationAccount, 
                       let new = newAccount,
                       dest.persistentModelID == new.persistentModelID {
                        destinationAccount = nil
                    }
                }
            }
        }
    }


    private var transferDestinationSection: some View {
        Section(lang["transfer.to"]) {
            Picker(lang["transfer.to"], selection: $destinationAccount) {
                Text(lang["label.none"] + "…").tag(Account?.none)
                ForEach(availableDestinationAccounts) { a in
                    HStack {
                        Image(systemName: a.iconSystemName)
                            .foregroundStyle(Color(hex: a.colorHex))
                        Text(a.name)
                        Text("(\(a.currency))").foregroundStyle(.secondary)
                    }
                    .tag(Optional(a))
                }
            }
        }
    }
    
    // Computed property for destination accounts (filters out selected account)
    private var availableDestinationAccounts: [Account] {
        guard let selected = selectedAccount else { return accounts }
        return accounts.filter { $0.persistentModelID != selected.persistentModelID }
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
                        Text(cat.localizedName).foregroundStyle(.primary)
                    } else {
                        Image(systemName: "tag").foregroundStyle(.secondary)
                        Text(lang["tx.noCategory"]).foregroundStyle(.secondary)
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
            TextField(type == .income ? lang["tx.payeeIncome"]
                                       : lang["tx.payeeExpense"],
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
                Label(lang["recurring.deletePrompt"], systemImage: "trash")
            }
        } footer: {
            Text(lang["recurring.deleteFooter"])
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

    // MARK: - Logic

    private func loadIfEditing() {
        guard case .edit(let rule) = mode else {
            // Create mode: default account
            selectedAccount = accounts.first
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
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
        isTransfer = rule.isTransfer
        destinationAccount = rule.destinationAccount
        notifEnabled = rule.notificationEnabled
        notifDaysBefore = rule.notificationDaysBefore
    }

    private func save() {
        guard let amount = parsedAmount, amount > 0,
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
            rule.isTransfer = isTransfer
            rule.destinationAccount = isTransfer ? destinationAccount : nil
            rule.notificationEnabled = notifEnabled
            rule.notificationDaysBefore = notifDaysBefore
            context.insert(rule)
            
            // Save context first, then apply pending async
            do {
                try context.save()
                dismiss()
                
                // Apply pending transactions in background after UI dismisses
                Task {
                    RecurringTransactionManager.applyPending(context: context)
                    await NotificationManager.shared.scheduleAll(context: context)
                }
            } catch {
                print("AddEditRecurringTransactionView: save failed — \(error)")
            }

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
            rule.isTransfer = isTransfer
            rule.destinationAccount = isTransfer ? destinationAccount : nil
            rule.notificationEnabled = notifEnabled
            rule.notificationDaysBefore = notifDaysBefore
            
            do {
                try context.save()
                dismiss()
                
                // Schedule notifications async after UI dismisses
                Task {
                    await NotificationManager.shared.scheduleAll(context: context)
                }
            } catch {
                print("AddEditRecurringTransactionView: save failed — \(error)")
            }
        }
    }

    private func deleteIfEditing() {
        guard case .edit(let rule) = mode else { return }
        context.delete(rule)
        
        do {
            try context.save()
            dismiss()
            
            // Schedule notifications async after successful deletion and UI dismisses
            Task {
                await NotificationManager.shared.scheduleAll(context: context)
            }
        } catch {
            print("AddEditRecurringTransactionView: delete failed — \(error)")
        }
    }

    private func parseAmount() -> Decimal? {
        let normalized = amountText
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        guard !normalized.isEmpty else { return nil }
        return Decimal(string: normalized)
    }

    private func decimalToText(_ d: Decimal) -> String {
        d.appFormattedForInput
    }
}

// MARK: - Category picker (reuse logic, local copy to avoid cross-file private)

private struct CategoryPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LanguageManager.self) private var lang
    let type: TransactionType
    let categories: [Category]
    @Binding var selected: Category?
    
    private let columns = [
        GridItem(.adaptive(minimum: 90, maximum: 120), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    CategoryTile(
                        name: "Aucune",
                        icon: "circle.dashed",
                        color: .gray,
                        isSelected: selected == nil
                    ) {
                        selected = nil
                        dismiss()
                    }
                    
                    ForEach(categories) { cat in
                        CategoryTile(
                            name: cat.localizedName,
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
                    Button(lang["action.close"]) { dismiss() }
                }
            }
        }
    }
}

// Extract tile to separate view for better performance
private struct CategoryTile: View {
    let name: String
    let icon: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
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
                    .stroke(
                        isSelected ? color : Color(.separator),
                        lineWidth: isSelected ? 2 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
