//
//  AddEditSavingsProjectView.swift
//  FinTrack
//

import SwiftUI
import SwiftData

enum SavingsProjectEditorMode {
    case create
    case edit(SavingsProject)
}

struct AddEditSavingsProjectView: View {
    @Environment(\.modelContext) private var context
    @Environment(LanguageManager.self) private var lang
    @Environment(\.dismiss) private var dismiss

    let mode: SavingsProjectEditorMode

    @Query(filter: #Predicate<Account> { !$0.isArchived },
           sort: \Account.createdAt, order: .forward)
    private var accounts: [Account]

    // MARK: State

    @State private var name: String = ""
    @State private var iconSystemName: String = "star.fill"
    @State private var colorHex: String = ColorPalette.accountColors[1]
    @State private var currency: String = Currencies.default
    @State private var currentAmountText: String = "0"
    @State private var trackViaAccount: Bool = false
    @State private var selectedAccount: Account? = nil
    @State private var hasTarget: Bool = true
    @State private var targetAmountText: String = ""
    @State private var contributionText: String = ""
    @State private var hasDeadline: Bool = false
    @State private var targetDate: Date = Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now
    @State private var notes: String = ""
    @State private var showDeleteConfirm: Bool = false

    // Recurring contribution
    @State private var createRecurring: Bool = false
    @State private var contributionSourceAccount: Account? = nil

    private var isEditing: Bool { if case .edit = mode { return true }; return false }
    private var navTitle: String { isEditing ? lang["savings.edit"] : lang["savings.createNew"] }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    // MARK: Computed

    private var currentDecimal: Decimal {
        Decimal(Double(currentAmountText.replacingOccurrences(of: ",", with: ".")) ?? 0)
    }
    private var targetDecimal: Decimal? {
        hasTarget ? Decimal(Double(targetAmountText.replacingOccurrences(of: ",", with: ".")) ?? 0) : nil
    }
    private var contributionDecimal: Decimal {
        Decimal(Double(contributionText.replacingOccurrences(of: ",", with: ".")) ?? 0)
    }
    private var hasContribution: Bool {
        (contributionDecimal as NSDecimalNumber).doubleValue > 0
    }

    private var previewProject: SavingsProject {
        SavingsProject(
            name: name, iconSystemName: iconSystemName, colorHex: colorHex,
            currency: currency,
            currentAmount: trackViaAccount ? (selectedAccount?.balance ?? currentDecimal) : currentDecimal,
            trackViaAccount: false,
            targetAmount: targetDecimal,
            monthlyContribution: contributionDecimal,
            targetDate: hasDeadline ? targetDate : nil
        )
    }

    // MARK: Icon choices

    private let iconChoices = [
        "star.fill", "airplane", "house.fill", "car.fill", "heart.fill",
        "graduationcap.fill", "briefcase.fill", "gift.fill", "leaf.fill",
        "shield.fill", "waveform.path.ecg", "globe", "sun.max.fill",
        "moon.stars.fill", "camera.fill", "music.note", "gamecontroller.fill",
        "fork.knife", "pawprint.fill", "cross.case.fill"
    ]

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                identitySection
                currentAmountSection
                targetSection
                contributionSection
                if hasTarget && !hasDeadline { livePreviewSection }
                if hasDeadline              { deadlinePreviewSection }
                notesSection
                if isEditing { deleteSection }
            }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading)  { Button(lang["action.cancel"]) { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(lang["action.save"]) { save() }
                        .disabled(!canSave).fontWeight(.semibold)
                }
            }
            .confirmationDialog(lang["savings.delete"], isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button(lang["action.delete"], role: .destructive) { deleteIfEditing() }
                Button(lang["action.cancel"], role: .cancel) {}
            }
            .onAppear(perform: loadIfEditing)
        }
    }

    // MARK: - Sections

    private var identitySection: some View {
        Section(lang["savings.project.identify"]) {
            TextField(lang["savings.project.name.hint"], text: $name)

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
                                .foregroundStyle(icon == iconSystemName
                                                 ? ColorPalette.foregroundColor(on: colorHex)
                                                 : .primary)
                                .onTapGesture { iconSystemName = icon }
                        }
                    }.padding(.vertical, 4)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(lang["label.color"]).font(.subheadline)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(ColorPalette.accountColors, id: \.self) { hex in
                            Circle().fill(Color(hex: hex)).frame(width: 32, height: 32)
                                .overlay {
                                    Circle().strokeBorder(Color(.separator),
                                                          lineWidth: hex == "#F2F2F7" ? 1 : 0)
                                    if hex == colorHex {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(ColorPalette.foregroundColor(on: hex))
                                            .font(.system(size: 14, weight: .bold))
                                    }
                                }
                                .onTapGesture { colorHex = hex }
                        }
                    }.padding(.vertical, 4)
                }
            }

            Picker(lang["label.currency"], selection: $currency) {
                ForEach(Currencies.all) { c in Text("\(c.code) — \(c.nameFR)").tag(c.code) }
            }
        }
    }

    private var currentAmountSection: some View {
        Section {
            Toggle(isOn: $trackViaAccount.animation()) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(lang["savings.trackViaAccount"])
                    Text(lang["savings.trackViaAccount.sub"])
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if trackViaAccount {
                Picker(lang["label.account"], selection: $selectedAccount) {
                    Text(lang["label.none"] + "…").tag(Account?.none)
                    ForEach(accounts) { acc in
                        HStack {
                            Image(systemName: acc.iconSystemName).foregroundStyle(Color(hex: acc.colorHex))
                            Text(acc.name)
                        }.tag(Optional(acc))
                    }
                }
                if let acc = selectedAccount {
                    HStack {
                        Text(lang["savings.currentAmount"]).foregroundStyle(.secondary)
                        Spacer()
                        Text(acc.balance.formatted(asCurrency: acc.currency))
                            .font(.body.weight(.semibold))
                    }
                }
            } else {
                HStack {
                    Text(lang["savings.alreadySaved"])
                    Spacer()
                    TextField("0", text: $currentAmountText)
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(maxWidth: 120)
                    Text(Currencies.info(for: currency).symbol).foregroundStyle(.secondary)
                }
            }
        } header: { Text(lang["savings.currentAmount.section"]) }
    }

    private var targetSection: some View {
        Section {
            Toggle(lang["savings.defineTarget"], isOn: $hasTarget.animation())
            if hasTarget {
                HStack {
                    Text(lang["savings.targetAmount"])
                    Spacer()
                    TextField("0", text: $targetAmountText)
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(maxWidth: 120)
                    Text(Currencies.info(for: currency).symbol).foregroundStyle(.secondary)
                }
                Toggle(isOn: $hasDeadline.animation()) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lang["savings.deadline"])
                        Text(lang["savings.deadline.sub"])
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if hasDeadline {
                    DatePicker(lang["savings.deadline.before"],
                               selection: $targetDate,
                               in: Date()...,
                               displayedComponents: .date)
                }
            }
        } header: { Text(lang["savings.target"]) }
    }

    private var contributionSection: some View {
        Section {
            // Contribution amount
            HStack {
                Text(lang["savings.contribution"])
                Spacer()
                TextField("0", text: $contributionText)
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(maxWidth: 120)
                Text(Currencies.info(for: currency).symbol).foregroundStyle(.secondary)
            }

            // Recurring transfer toggle (only relevant when a contribution is set)
            if hasContribution {
                Toggle(isOn: $createRecurring.animation()) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lang["savings.recurring.toggle"])
                        Text(lang["savings.recurring.toggle.sub"])
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                if createRecurring {
                    // Source account picker (where money is debited from)
                    Picker(lang["savings.recurring.source"], selection: $contributionSourceAccount) {
                        Text(lang["prepayment.account.none"]).tag(Account?.none)
                        ForEach(accounts.filter { $0.id != selectedAccount?.id }) { acc in
                            Label {
                                HStack {
                                    Text(acc.name)
                                    Text("(\(acc.currency))").foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: acc.iconSystemName.isEmpty
                                      ? acc.type.defaultIconSystemName
                                      : acc.iconSystemName)
                                    .foregroundStyle(Color(hex: acc.colorHex))
                            }
                            .tag(Optional(acc))
                        }
                    }

                    // Destination preview (savings account if tracked, or none)
                    if trackViaAccount, let savings = selectedAccount {
                        HStack {
                            Text(lang["savings.recurring.destination"])
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(savings.name)
                                .foregroundStyle(.green)
                        }
                    }
                }
            }
        } header: {
            Text(lang["savings.contribution.section"])
        } footer: {
            if createRecurring && hasContribution {
                Text(lang["savings.recurring.toggle.sub"])
            } else {
                Text(lang["savings.contribution.footer"])
            }
        }
    }

    @ViewBuilder
    private var livePreviewSection: some View {
        let p = previewProject
        if hasContribution,
           let target = targetDecimal,
           (target as NSDecimalNumber).doubleValue > 0 {
            Section {
                if let reachDate = p.targetReachDate, let months = p.monthsToTarget {
                    summaryRow(lang["savings.projection.onTrack"],
                               value: reachDate.appFormattedLong(),
                               emphasis: true)
                    summaryRow(lang["savings.projection.duration"],
                               value: String(format: lang["savings.projection.months"], months))
                } else if (currentDecimal as NSDecimalNumber).doubleValue >= ((target) as NSDecimalNumber).doubleValue {
                    Label(lang["savings.projection.reached"], systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            } header: { Text(lang["savings.projection"]) }
        }
    }

    @ViewBuilder
    private var deadlinePreviewSection: some View {
        let p = previewProject
        Section {
            if let req = p.requiredMonthlyForDeadline {
                summaryRow(lang["savings.projection.required"],
                           value: req.formatted(asCurrency: currency) + lang["savings.perMonth"],
                           emphasis: true,
                           color: req > contributionDecimal && hasContribution ? .orange : .green)
            }
        } header: { Text(lang["savings.requiredContrib"]) }
    }

    private var notesSection: some View {
        Section(lang["savings.notes.section"]) {
            TextField(lang["savings.notes.placeholder"], text: $notes, axis: .vertical)
                .lineLimit(2...4)
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) { showDeleteConfirm = true } label: {
                Label(lang["savings.delete"], systemImage: "trash")
            }
        }
    }

    // MARK: - Helpers

    private func summaryRow(_ label: String, value: String,
                            emphasis: Bool = false, color: Color = .primary) -> some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(emphasis ? .body.weight(.semibold) : .body)
                .foregroundStyle(emphasis ? Color.accentColor : color)
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: - Logic

    private func loadIfEditing() {
        guard case .edit(let p) = mode else { return }
        name                 = p.name
        iconSystemName       = p.iconSystemName
        colorHex             = p.colorHex
        currency             = p.currency
        trackViaAccount      = p.trackViaAccount
        selectedAccount      = p.account
        currentAmountText    = decimalToText(p.manualCurrentAmount)
        hasTarget            = p.targetAmount != nil
        targetAmountText     = p.targetAmount.map { decimalToText($0) } ?? ""
        contributionText     = decimalToText(p.monthlyContribution)
        hasDeadline          = p.targetDate != nil
        if let d = p.targetDate { targetDate = d }
        notes                = p.notes ?? ""
        // createRecurring stays false in edit mode — manage existing rules separately
    }

    private func save() {
        let trimName = name.trimmingCharacters(in: .whitespaces)
        let current  = trackViaAccount
            ? (selectedAccount?.balance ?? currentDecimal)
            : currentDecimal

        switch mode {
        case .create:
            let p = SavingsProject(
                name: trimName, iconSystemName: iconSystemName, colorHex: colorHex,
                currency: currency, currentAmount: current,
                trackViaAccount: trackViaAccount,
                targetAmount: hasTarget ? targetDecimal : nil,
                monthlyContribution: contributionDecimal,
                targetDate: hasTarget && hasDeadline ? targetDate : nil,
                account: selectedAccount,
                notes: notes.trimmingCharacters(in: .whitespaces).isEmpty
                    ? nil : notes.trimmingCharacters(in: .whitespaces)
            )
            context.insert(p)

            // Create recurring monthly transfer if requested
            if createRecurring, hasContribution, let source = contributionSourceAccount {
                let startDate = firstOfNextMonth()
                let ruleName  = trimName.isEmpty ? lang["savings.title"] : trimName

                if trackViaAccount, let savings = selectedAccount {
                    // Transfer: debit source → credit savings account
                    let rule = RecurringTransaction(
                        title: ruleName,
                        amount: contributionDecimal,
                        type: .expense,
                        frequency: .monthly,
                        startDate: startDate,
                        account: source,
                        note: lang["savings.contribution"] + " — " + ruleName,
                        payee: nil,
                        isLoanPayment: false
                    )
                    rule.isTransfer        = true
                    rule.destinationAccount = savings
                    context.insert(rule)
                } else {
                    // Simple expense on source account
                    let rule = RecurringTransaction(
                        title: ruleName,
                        amount: contributionDecimal,
                        type: .expense,
                        frequency: .monthly,
                        startDate: startDate,
                        account: source,
                        note: lang["savings.contribution"] + " — " + ruleName,
                        payee: nil,
                        isLoanPayment: false
                    )
                    context.insert(rule)
                }
            }

        case .edit(let p):
            p.name              = trimName
            p.iconSystemName    = iconSystemName
            p.colorHex          = colorHex
            p.currency          = currency
            p.manualCurrentAmount = current
            p.trackViaAccount   = trackViaAccount
            p.account           = selectedAccount
            p.targetAmount      = hasTarget ? targetDecimal : nil
            p.monthlyContribution = contributionDecimal
            p.targetDate        = hasTarget && hasDeadline ? targetDate : nil
            p.notes = notes.trimmingCharacters(in: .whitespaces).isEmpty
                ? nil : notes.trimmingCharacters(in: .whitespaces)
        }

        try? context.save()
        // Generate any past occurrences immediately (synchronous, like AddEditLoanView)
        RecurringTransactionManager.applyPending(context: context)
        dismiss()
    }

    private func deleteIfEditing() {
        guard case .edit(let p) = mode else { return }
        context.delete(p)
        try? context.save()
        dismiss()
    }

    /// Returns the 1st day of next month as the first contribution date.
    private func firstOfNextMonth() -> Date {
        let cal = Calendar.current
        let now = Date()
        guard let nextMonth = cal.date(byAdding: .month, value: 1, to: now) else { return now }
        let components = cal.dateComponents([.year, .month], from: nextMonth)
        return cal.date(from: components) ?? nextMonth
    }

    private func decimalToText(_ d: Decimal) -> String {
        return d.appFormattedForInput
    }
}
