//
//  AddEditAccountView.swift
//  FinTrack
//

import SwiftUI
import SwiftData

enum AccountEditorMode {
    case create
    case edit(Account)
}

struct AddEditAccountView: View {
    @Environment(\.modelContext) private var context
    @Environment(LanguageManager.self) private var lang
    @Environment(EntitlementManager.self) private var entitlements
    @Environment(\.dismiss) private var dismiss

    let mode: AccountEditorMode

    @State private var name: String = ""
    @State private var institution: String = ""
    @State private var type: AccountType = .checking
    @State private var currency: String = Currencies.default
    @State private var initialBalanceText: String = "0"
    @State private var colorHex: String = ColorPalette.accountColors.first ?? "#3478F6"
    @State private var iconSystemName: String = AccountType.checking.defaultIconSystemName
    @State private var notes: String = ""
    @State private var bankDomain: String? = nil   // domain for logo; set on institution selection

    /// CAD + USD for free tier; all currencies for Pro.
    private var availableCurrencies: [CurrencyInfo] {
        if entitlements.hasPro { return Currencies.all }
        return Currencies.all.filter { ["CAD", "USD"].contains($0.code) }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var navTitle: String {
        isEditing ? lang["account.edit"] : lang["account.create"]
    }

    /// Foreground color for icons displayed on the selected colorHex background.
    private var iconForeground: Color {
        ColorPalette.foregroundColor(on: colorHex)
    }

    /// Sentinel: empty string means "use institution logo, no SF Symbol".
    private static let noIconSentinel = ""

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !institution.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(lang["label.information"]) {
                    TextField(lang["label.name"], text: $name)
                    InstitutionPickerField(
                        text: $institution,
                        placeholder: lang["label.institution"],
                        onBankSelected: { bank in
                            bankDomain = bank.domain
                            // Auto-select "no icon" so the logo is shown by default
                            iconSystemName = Self.noIconSentinel
                            // Auto-set a colour matching the institution's region
                            if let hex = institutionColor(for: bank) {
                                colorHex = hex
                            }
                        },
                        hasPro: entitlements.hasPro
                    )
                    Picker(lang["label.type"], selection: $type) {
                        ForEach(AccountType.allCases) { t in
                            Text(t.label).tag(t)
                        }
                    }
                    .onChange(of: type) { _, newType in
                        // Auto-update icon to type default if user hasn't customized.
                        if iconSystemName == newType.defaultIconSystemName ||
                           AccountType.allCases.map(\.defaultIconSystemName).contains(iconSystemName) {
                            iconSystemName = newType.defaultIconSystemName
                        }
                    }
                }

                Section(lang["label.currency"]) {
                    Picker(lang["label.currency"], selection: $currency) {
                        ForEach(availableCurrencies) { cur in
                            Text("\(cur.code) — \(cur.nameFR)").tag(cur.code)
                        }
                    }
                    if !entitlements.hasPro {
                        Label(lang["account.currency.proHint"], systemImage: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text(lang["account.initialBalance"])
                        Spacer()
                        TextField("0", text: $initialBalanceText)
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 140)
                        Text(Currencies.info(for: currency).symbol)
                            .foregroundStyle(.secondary)
                    }
                }

                Section(lang["label.appearance"]) {
                    colorPicker
                    iconPicker
                }

                Section(lang["label.notes"] + " " + lang["label.optional"]) {
                    TextField(lang["label.notes"], text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }

                if case .edit(let account) = mode {
                    Section {
                        Button(role: .destructive) {
                            delete(account)
                        } label: {
                            Label(lang["account.deleteDefinitive"], systemImage: "trash")
                        }
                    } footer: {
                        Text(lang["account.deleteFooter"])
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
            .onAppear {
                loadIfEditing()
                // Ensure selected currency is available in current tier
                if !availableCurrencies.contains(where: { $0.code == currency }) {
                    currency = Currencies.default
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
                                // Stroke for light colours so they're visible on any background
                                Circle()
                                    .strokeBorder(Color(.separator), lineWidth: hex == "#F2F2F7" ? 1 : 0)
                                if hex == colorHex {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(ColorPalette.foregroundColor(on: hex))
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
        let icons: [String] = Array(Set(AccountType.allCases.map(\.defaultIconSystemName) + [
            "creditcard.fill", "banknote.fill", "dollarsign.circle.fill",
            "building.columns.fill", "chart.line.uptrend.xyaxis", "wallet.pass.fill",
            "bitcoinsign.circle.fill", "house.fill", "globe", "briefcase.fill"
        ])).sorted()
        let isLogoSelected = iconSystemName == Self.noIconSentinel

        return VStack(alignment: .leading, spacing: 8) {
            Text(lang["label.icon"]).font(.subheadline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    // ── "Logo" tile (sentinel — displays institution logo) ──
                    ZStack {
                        Circle()
                            .fill(isLogoSelected
                                  ? Color(hex: colorHex)
                                  : Color(.tertiarySystemBackground))
                            .frame(width: 40, height: 40)
                        if let domain = bankDomain {
                            BankLogoView(domain: domain, size: 26, cornerRadius: 6)
                        } else {
                            // No institution matched yet — show a bank placeholder
                            Image(systemName: "building.columns")
                                .font(.system(size: 16))
                                .foregroundStyle(isLogoSelected ? iconForeground : .secondary)
                        }
                        if isLogoSelected {
                            // Small checkmark badge
                            Circle()
                                .fill(Color.green)
                                .frame(width: 14, height: 14)
                                .overlay(
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 7, weight: .bold))
                                        .foregroundStyle(.white)
                                )
                                .offset(x: 12, y: 12)
                        }
                    }
                    .frame(width: 40, height: 40)
                    .onTapGesture { iconSystemName = Self.noIconSentinel }

                    // ── SF Symbol tiles ───────────────────────────────────
                    ForEach(icons, id: \.self) { name in
                        let isSelected = name == iconSystemName
                        Image(systemName: name)
                            .font(.system(size: 18))
                            .frame(width: 40, height: 40)
                            .background(
                                isSelected
                                    ? Color(hex: colorHex)
                                    : Color(.tertiarySystemBackground),
                                in: Circle()
                            )
                            .foregroundStyle(isSelected ? iconForeground : .primary)
                            .onTapGesture { iconSystemName = name }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Logic

    /// Maps a known bank to a brand-appropriate color from the palette.
    private func institutionColor(for bank: BankInfo) -> String? {
        switch bank.countryCode {
        case "CA": return "#FF3B30"   // Canadian red
        case "US": return "#3478F6"   // Blue
        case "GB": return "#3478F6"   // Blue
        case "FR": return "#3478F6"   // Blue
        case "AF": return "#34C759"   // Green
        default:   return nil
        }
    }


    private func loadIfEditing() {
        guard case .edit(let account) = mode else { return }
        name = account.name
        institution = account.institution
        type = account.type
        currency = account.currency
        initialBalanceText = decimalToText(account.initialBalance)
        colorHex = account.colorHex
        iconSystemName = account.iconSystemName
        bankDomain = account.bankDomain
        notes = account.notes ?? ""
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedInst = institution.trimmingCharacters(in: .whitespaces)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespaces)
        let initial = parseDecimal(initialBalanceText) ?? 0

        switch mode {
        case .create:
            let account = Account(
                name: trimmedName,
                institution: trimmedInst,
                type: type,
                currency: currency,
                initialBalance: initial,
                colorHex: colorHex,
                iconSystemName: iconSystemName,
                notes: trimmedNotes.isEmpty ? nil : trimmedNotes
            )
            account.bankDomain = bankDomain
            context.insert(account)
        case .edit(let account):
            account.name = trimmedName
            account.institution = trimmedInst
            account.type = type
            account.currency = currency
            account.initialBalance = initial
            account.colorHex = colorHex
            account.iconSystemName = iconSystemName
            account.bankDomain = bankDomain
            account.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
        }

        do {
            try context.save()
            dismiss()
        } catch {
            print("AddEditAccountView: save failed — \(error)")
        }
    }

    private func delete(_ account: Account) {
        context.delete(account)
        try? context.save()
        dismiss()
    }

    // Accept both "1234.56" and "1234,56" (FR convention) for the initial balance.
    private func parseDecimal(_ s: String) -> Decimal? {
        let normalized = s.replacingOccurrences(of: ",", with: ".")
                          .trimmingCharacters(in: .whitespaces)
        return Decimal(string: normalized)
    }

    private func decimalToText(_ d: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "fr_CA")
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSDecimalNumber(decimal: d)) ?? "\(d)"
    }
}
