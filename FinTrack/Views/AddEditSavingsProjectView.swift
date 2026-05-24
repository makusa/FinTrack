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
    @State private var colorHex: String = ColorPalette.accountColors[1] // green
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

    private var isEditing: Bool { if case .edit = mode { return true }; return false }
    private var navTitle: String { isEditing ? lang["savings.edit"] : lang["savings.createNew"] }

    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    // MARK: Live preview

    private var currentDecimal: Decimal {
        Decimal(Double(currentAmountText.replacingOccurrences(of: ",", with: ".")) ?? 0)
    }
    private var targetDecimal: Decimal? {
        hasTarget ? Decimal(Double(targetAmountText.replacingOccurrences(of: ",", with: ".")) ?? 0) : nil
    }
    private var contributionDecimal: Decimal {
        Decimal(Double(contributionText.replacingOccurrences(of: ",", with: ".")) ?? 0)
    }

    private var previewProject: SavingsProject {
        let p = SavingsProject(
            name: name, iconSystemName: iconSystemName, colorHex: colorHex,
            currency: currency,
            currentAmount: trackViaAccount ? (selectedAccount?.balance ?? currentDecimal) : currentDecimal,
            trackViaAccount: false,
            targetAmount: targetDecimal,
            monthlyContribution: contributionDecimal,
            targetDate: hasDeadline ? targetDate : nil
        )
        return p
    }

    // MARK: Icon choices

    private let iconChoices = [
        "star.fill", "airplane", "house.fill", "car.fill", "heart.fill",
        "graduationcap.fill", "briefcase.fill", "gift.fill", "leaf.fill",
        "shield.fill", "waveform.path.ecg", "globe", "sun.max.fill",
        "moon.stars.fill", "camera.fill", "music.note", "gamecontroller.fill",
        "fork.knife", "pawprint.fill", "cross.case.fill"
    ]

    var body: some View {
        NavigationStack {
            Form {
                identitySection
                currentAmountSection
                targetSection
                contributionSection
                if hasTarget && !hasDeadline { livePreviewSection }
                if hasDeadline           { deadlinePreviewSection }
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
        Section("Identification") {
            TextField("Nom du projet (ex. Voyage Cameroun)", text: $name)

            // Icon picker
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
                    }.padding(.vertical, 4)
                }
            }

            // Color picker
            VStack(alignment: .leading, spacing: 8) {
                Text(lang["label.color"]).font(.subheadline)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(ColorPalette.accountColors, id: \.self) { hex in
                            Circle().fill(Color(hex: hex)).frame(width: 32, height: 32)
                                .overlay {
                                    if hex == colorHex {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.white)
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
                    DatePicker("Atteindre l'objectif avant le", selection: $targetDate,
                               in: Date()..., displayedComponents: .date)
                }
            }
        } header: { Text(lang["savings.target"]) }
    }

    private var contributionSection: some View {
        Section {
            HStack {
                Text(lang["savings.contribution"])
                Spacer()
                TextField("0", text: $contributionText)
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(maxWidth: 120)
                Text(Currencies.info(for: currency).symbol).foregroundStyle(.secondary)
            }
        } header: {
            Text(lang["savings.contribution.section"])
        } footer: {
            Text(lang["savings.contribution.footer"])
        }
    }

    @ViewBuilder
    private var livePreviewSection: some View {
        let p = previewProject
        if (contributionDecimal as NSDecimalNumber).doubleValue > 0,
           let target = targetDecimal, (target as NSDecimalNumber).doubleValue > 0 {
            Section {
                if let reachDate = p.targetReachDate, let months = p.monthsToTarget {
                    summaryRow("À ce rythme, vous atteindrez l'objectif le",
                               value: reachDate.formatted(date: .long, time: .omitted),
                               emphasis: true)
                    summaryRow("Durée estimée", value: "\(months) mois")
                } else if (currentDecimal as NSDecimalNumber).doubleValue >= (target as NSDecimalNumber).doubleValue {
                    Label("Objectif déjà atteint ! 🎉", systemImage: "checkmark.circle.fill")
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
                summaryRow("Contribution requise pour l'échéance",
                           value: req.formatted(asCurrency: currency) + "/mois",
                           emphasis: true,
                           color: req > contributionDecimal && (contributionDecimal as NSDecimalNumber).doubleValue > 0 ? .orange : .green)
            }
        } header: { Text(lang["savings.requiredContrib"]) }
    }

    private var notesSection: some View {
        Section("Notes (optionnel)") {
            TextField("Détails, motivation, liens…", text: $notes, axis: .vertical).lineLimit(2...4)
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) { showDeleteConfirm = true } label: {
                Label(lang["savings.delete"], systemImage: "trash")
            }
        }
    }

    // MARK: Helpers

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

    // MARK: Logic

    private func loadIfEditing() {
        guard case .edit(let p) = mode else { return }
        name = p.name
        iconSystemName = p.iconSystemName
        colorHex = p.colorHex
        currency = p.currency
        trackViaAccount = p.trackViaAccount
        selectedAccount = p.account
        currentAmountText = decimalToText(p.manualCurrentAmount)
        hasTarget = p.targetAmount != nil
        targetAmountText = p.targetAmount.map { decimalToText($0) } ?? ""
        contributionText = decimalToText(p.monthlyContribution)
        hasDeadline = p.targetDate != nil
        if let d = p.targetDate { targetDate = d }
        notes = p.notes ?? ""
    }

    private func save() {
        let trimName = name.trimmingCharacters(in: .whitespaces)
        let current = trackViaAccount ? (selectedAccount?.balance ?? currentDecimal) : currentDecimal

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
                notes: notes.trimmingCharacters(in: .whitespaces).isEmpty ? nil : notes.trimmingCharacters(in: .whitespaces)
            )
            context.insert(p)
        case .edit(let p):
            p.name = trimName; p.iconSystemName = iconSystemName; p.colorHex = colorHex
            p.currency = currency; p.manualCurrentAmount = current
            p.trackViaAccount = trackViaAccount; p.account = selectedAccount
            p.targetAmount = hasTarget ? targetDecimal : nil
            p.monthlyContribution = contributionDecimal
            p.targetDate = hasTarget && hasDeadline ? targetDate : nil
            p.notes = notes.trimmingCharacters(in: .whitespaces).isEmpty ? nil : notes
        }
        try? context.save()
        dismiss()
    }

    private func deleteIfEditing() {
        guard case .edit(let p) = mode else { return }
        context.delete(p); try? context.save(); dismiss()
    }

    private func decimalToText(_ d: Decimal) -> String {
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal; fmt.locale = Locale(identifier: "fr_CA")
        fmt.maximumFractionDigits = 2; fmt.minimumFractionDigits = 0
        fmt.usesGroupingSeparator = false
        return fmt.string(from: NSDecimalNumber(decimal: d)) ?? "\(d)"
    }
}
