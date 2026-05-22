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

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var navTitle: String {
        isEditing ? "Modifier le compte" : "Nouveau compte"
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !institution.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Informations") {
                    TextField("Nom (ex. BNC Courant)", text: $name)
                    TextField("Institution (ex. Banque Nationale)", text: $institution)
                    Picker("Type", selection: $type) {
                        ForEach(AccountType.allCases) { t in
                            Text(t.labelFR).tag(t)
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

                Section("Devise") {
                    Picker("Devise", selection: $currency) {
                        ForEach(Currencies.all) { c in
                            Text("\(c.code) — \(c.nameFR)").tag(c.code)
                        }
                    }
                    HStack {
                        Text("Solde initial")
                        Spacer()
                        TextField("0", text: $initialBalanceText)
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 140)
                        Text(Currencies.info(for: currency).symbol)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Apparence") {
                    colorPicker
                    iconPicker
                }

                Section("Notes (optionnel)") {
                    TextField("Numéro de compte, branche, etc.", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }

                if case .edit(let account) = mode {
                    Section {
                        Button(role: .destructive) {
                            delete(account)
                        } label: {
                            Label("Supprimer définitivement", systemImage: "trash")
                        }
                    } footer: {
                        Text("La suppression efface ce compte et toutes ses transactions. Préférez l'archivage si vous souhaitez les conserver.")
                    }
                }
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
            .onAppear(perform: loadIfEditing)
        }
    }

    // MARK: - Sub-views

    private var colorPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Couleur").font(.subheadline)
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
            Text("Icône").font(.subheadline)
            let icons = Array(Set(AccountType.allCases.map(\.defaultIconSystemName) + [
                "creditcard.fill", "banknote.fill", "dollarsign.circle.fill",
                "building.columns.fill", "chart.line.uptrend.xyaxis", "wallet.pass.fill",
                "bitcoinsign.circle.fill", "house.fill", "globe", "briefcase.fill"
            ])).sorted()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(icons, id: \.self) { name in
                        Image(systemName: name)
                            .font(.system(size: 18))
                            .frame(width: 40, height: 40)
                            .background(
                                name == iconSystemName
                                    ? Color(hex: colorHex)
                                    : Color(.tertiarySystemBackground),
                                in: Circle()
                            )
                            .foregroundStyle(name == iconSystemName ? .white : .primary)
                            .onTapGesture { iconSystemName = name }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Logic

    private func loadIfEditing() {
        guard case .edit(let account) = mode else { return }
        name = account.name
        institution = account.institution
        type = account.type
        currency = account.currency
        initialBalanceText = decimalToText(account.initialBalance)
        colorHex = account.colorHex
        iconSystemName = account.iconSystemName
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
            context.insert(account)
        case .edit(let account):
            account.name = trimmedName
            account.institution = trimmedInst
            account.type = type
            account.currency = currency
            account.initialBalance = initial
            account.colorHex = colorHex
            account.iconSystemName = iconSystemName
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
