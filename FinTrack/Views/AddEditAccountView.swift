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

    // Credit-card fields (used only when type == .credit)
    @State private var ccLimitText: String = ""
    @State private var ccStatementDay: Int = 1
    @State private var ccDueDay: Int = 21
    @State private var ccAPRText: String = ""
    @State private var ccNetwork: CardNetwork = .other
    @State private var ccLastFour: String = ""
    @State private var ccMinType: MinimumPaymentType = .percentBalance
    @State private var ccMinValueText: String = ""

    // Registered account (CELI/CELIAPP)
    @State private var registeredType: RegisteredType? = nil

    /// CAD + USD for free tier; all currencies for Pro.
    private var availableCurrencies: [CurrencyInfo] {
        if entitlements.hasPaidTier { return Currencies.all }
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
                        hasPaidTier: entitlements.hasPaidTier
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
                    if !entitlements.hasPaidTier {
                        Label(lang["account.currency.proHint"], systemImage: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text(type == .credit ? lang["card.currentOwed"] : lang["account.initialBalance"])
                        Spacer()
                        TextField("0", text: $initialBalanceText)
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 140)
                        Text(Currencies.info(for: currency).symbol)
                            .foregroundStyle(.secondary)
                    }
                }

                if type == .credit {
                    creditCardSection
                }

                if type == .savings || type == .investment {
                    registeredSection
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
                                .foregroundStyle(isLogoSelected ? AnyShapeStyle(iconForeground) : AnyShapeStyle(.secondary))
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
                            .foregroundStyle(isSelected ? AnyShapeStyle(iconForeground) : AnyShapeStyle(.primary))
                            .onTapGesture { iconSystemName = name }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Credit-card section

    @ViewBuilder
    private var creditCardSection: some View {
        Section(lang["card.section"]) {
            HStack {
                Text(lang["card.limit"])
                Spacer()
                TextField("0", text: $ccLimitText)
                    .keyboardType(.numbersAndPunctuation)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 140)
                Text(Currencies.info(for: currency).symbol).foregroundStyle(.secondary)
            }
            Picker(lang["card.network"], selection: $ccNetwork) {
                ForEach(CardNetwork.allCases) { n in Text(n.label).tag(n) }
            }
            HStack {
                Text(lang["card.lastFour"])
                Spacer()
                TextField("0000", text: $ccLastFour)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 90)
                    .onChange(of: ccLastFour) { _, v in
                        ccLastFour = String(v.filter(\.isNumber).prefix(4))
                    }
            }
        }

        Section(lang["card.cycle.section"]) {
            Picker(lang["card.statementDay"], selection: $ccStatementDay) {
                ForEach(1...31, id: \.self) { d in Text("\(d)").tag(d) }
            }
            Picker(lang["card.dueDay"], selection: $ccDueDay) {
                ForEach(1...31, id: \.self) { d in Text("\(d)").tag(d) }
            }
        }

        Section {
            HStack {
                Text(lang["card.apr"])
                Spacer()
                TextField("0", text: $ccAPRText)
                    .keyboardType(.numbersAndPunctuation)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 100)
                Text("%").foregroundStyle(.secondary)
            }
            Picker(lang["card.minPayment"], selection: $ccMinType) {
                ForEach(MinimumPaymentType.allCases) { mp in Text(mp.label).tag(mp) }
            }
            if ccMinType != .interestOnly {
                HStack {
                    Text(ccMinType == .percentBalance
                         ? lang["card.minPayment.percentLabel"]
                         : lang["card.minPayment.fixedLabel"])
                    Spacer()
                    TextField("0", text: $ccMinValueText)
                        .keyboardType(.numbersAndPunctuation)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 100)
                    Text(ccMinType == .percentBalance
                         ? "%" : Currencies.info(for: currency).symbol)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text(lang["card.interest.section"])
        } footer: {
            Text(lang["card.estimate.footer"])
        }
    }

    // MARK: - Registered-account section

    @ViewBuilder
    private var registeredSection: some View {
        Section {
            Picker(lang["reg.account.type"], selection: $registeredType) {
                Text(lang["reg.account.none"]).tag(RegisteredType?.none)
                ForEach([RegisteredType.celi, .celiapp]) { t in
                    Text(t.label).tag(Optional(t))
                }
            }
        } header: {
            Text(lang["reg.account.section"])
        } footer: {
            Text(lang["reg.account.footer"])
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
        // Credit cards store initialBalance negative (liability); show owed as positive.
        initialBalanceText = decimalToText(account.type == .credit ? -account.initialBalance : account.initialBalance)
        colorHex = account.colorHex
        iconSystemName = account.iconSystemName
        bankDomain = account.bankDomain
        notes = account.notes ?? ""

        if let cc = account.creditCardProfile {
            ccLimitText = cc.creditLimit == 0 ? "" : decimalToText(cc.creditLimit)
            ccStatementDay = cc.statementDayOfMonth
            ccDueDay = cc.paymentDueDayOfMonth
            ccAPRText = cc.purchaseAPR == 0 ? "" : decimalToText(cc.purchaseAPR)
            ccNetwork = cc.cardNetwork
            ccLastFour = cc.lastFour ?? ""
            ccMinType = cc.minimumPaymentType
            ccMinValueText = cc.minimumPaymentValue == 0 ? "" : decimalToText(cc.minimumPaymentValue)
        }

        registeredType = account.registeredProfile?.registeredType
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedInst = institution.trimmingCharacters(in: .whitespaces)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespaces)
        let entered = parseDecimal(initialBalanceText) ?? 0
        // Credit cards are liabilities: store the entered "amount owed" as negative.
        let initial = (type == .credit) ? -abs(entered) : entered

        let account: Account
        switch mode {
        case .create:
            let newAccount = Account(
                name: trimmedName,
                institution: trimmedInst,
                type: type,
                currency: currency,
                initialBalance: initial,
                colorHex: colorHex,
                iconSystemName: iconSystemName,
                notes: trimmedNotes.isEmpty ? nil : trimmedNotes
            )
            newAccount.bankDomain = bankDomain
            context.insert(newAccount)
            account = newAccount
        case .edit(let existing):
            existing.name = trimmedName
            existing.institution = trimmedInst
            existing.type = type
            existing.currency = currency
            existing.initialBalance = initial
            existing.colorHex = colorHex
            existing.iconSystemName = iconSystemName
            existing.bankDomain = bankDomain
            existing.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
            account = existing
        }

        syncCreditCardProfile(on: account)
        syncRegisteredProfile(on: account)
        account.recalculateBalance()  // initialBalance may have changed

        do {
            try context.save()
            dismiss()
        } catch {
            AppLogger.persistence.error("AddEditAccountView save failed: \(error, privacy: .private)")
        }
    }

    /// Creates, updates, or removes the 1:1 CreditCardProfile so it matches the
    /// account type and the card fields entered in the form.
    private func syncCreditCardProfile(on account: Account) {
        guard type == .credit else {
            if let existing = account.creditCardProfile {
                context.delete(existing)          // type changed away from credit
                account.creditCardProfile = nil
            }
            return
        }
        let profile: CreditCardProfile
        if let existing = account.creditCardProfile {
            profile = existing
        } else {
            profile = CreditCardProfile(creditLimit: 0)
            context.insert(profile)
            account.creditCardProfile = profile
        }
        profile.creditLimit = parseDecimal(ccLimitText) ?? 0
        profile.statementDayOfMonth = ccStatementDay
        profile.paymentDueDayOfMonth = ccDueDay
        profile.purchaseAPR = parseDecimal(ccAPRText) ?? 0
        profile.cardNetwork = ccNetwork
        let four = ccLastFour.trimmingCharacters(in: .whitespaces)
        profile.lastFour = four.isEmpty ? nil : four
        profile.minimumPaymentType = ccMinType
        profile.minimumPaymentValue = parseDecimal(ccMinValueText) ?? 0
    }

    /// Creates, updates, or removes the 1:1 RegisteredAccountProfile based on the
    /// selected registered type (only for savings/investment accounts).
    private func syncRegisteredProfile(on account: Account) {
        let registerable = (type == .savings || type == .investment)
        guard registerable, let regType = registeredType else {
            if let existing = account.registeredProfile {
                context.delete(existing)
                account.registeredProfile = nil
            }
            return
        }
        if let existing = account.registeredProfile {
            existing.registeredType = regType
        } else {
            let p = RegisteredAccountProfile(registeredType: regType)
            context.insert(p)
            account.registeredProfile = p
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
        return d.appFormattedForInput
    }
}
