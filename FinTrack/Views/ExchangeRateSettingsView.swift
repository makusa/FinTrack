//
//  ExchangeRateSettingsView.swift
//  FinTrack
//

import SwiftUI

struct ExchangeRateSettingsView: View {
    @Environment(LanguageManager.self) private var lang
    @Environment(ExchangeRateManager.self) private var rates
    @Environment(EntitlementManager.self) private var entitlements
    // Local state avoids triggering a global re-render cascade on every
    // picker scroll tick. The actual change is applied via onChange.
    @State private var selectedCurrency: String = ""
    @State private var showConvertedLocal: Bool = false

    /// Devises sélectionnables : CAD + USD pour Courant, toutes pour Pro.
    private var selectableCurrencies: [CurrencyInfo] {
        entitlements.hasPro
            ? Currencies.all
            : Currencies.all.filter { ["CAD", "USD"].contains($0.code) }
    }

    /// Devises affichées dans le tableau des taux : même filtre.
    private var displayableCurrencies: [CurrencyInfo] {
        Currencies.all.filter {
            entitlements.hasPro || ["CAD", "USD"].contains($0.code)
        }
    }

    var body: some View {
        List {
            // MARK: Display currency
            Section {
                Picker(lang["fx.displayCurrency"], selection: $selectedCurrency) {
                    ForEach(selectableCurrencies) { c in
                        HStack {
                            Text(c.symbol)
                                .frame(width: 40, alignment: .leading)
                                .foregroundStyle(.secondary)
                            Text(c.code + " — " + c.nameFR)
                        }
                        .tag(c.code)
                    }
                    if !entitlements.hasPro {
                        Label(lang["fx.pro.hint"], systemImage: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .pickerStyle(.navigationLink)

                Toggle(lang["fx.showConverted"], isOn: $showConvertedLocal)
                    .onChange(of: showConvertedLocal) { _, new in
                        rates.showConvertedAmounts = new
                    }
            } header: {
                Text(lang["fx.displayCurrency"])
            } footer: {
                Text(lang["fx.displayCurrency.footer"])
            }

            // MARK: Rate status
            Section(lang["fx.rates.section"]) {
                HStack {
                    Label(lang["fx.source"], systemImage: "network")
                    Spacer()
                    Text("exchangerate-api.com")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if rates.isLoading {
                    HStack {
                        ProgressView()
                        Text(lang["fx.loading"])
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 8)
                    }
                } else if let updated = rates.lastUpdated {
                    LabeledContent(lang["fx.lastUpdated"]) {
                        Text(updated.appFormattedDateTime())
                            .foregroundStyle(.secondary)
                    }
                }

                if let error = rates.lastError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Button {
                    Task { await rates.refresh() }
                } label: {
                    Label(lang["fx.refresh"], systemImage: "arrow.clockwise")
                }
                .disabled(rates.isLoading)
            }

            // MARK: Current rates
            if !rates.rates.isEmpty {
                Section(lang["fx.rates.current"]) {
                    let display = rates.displayCurrency
                    ForEach(displayableCurrencies.filter { $0.code != rates.baseCurrency }, id: \.code) { currency in
                        let rate = rates.convert(1, from: rates.baseCurrency, to: currency.code)
                        HStack {
                            Text("1 \(rates.baseCurrency)")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("= \(rate.formatted(asCurrency: currency.code))")
                                .font(.body.weight(currency.code == display ? .semibold : .regular))
                                .foregroundStyle(currency.code == display ? Color.accentColor : Color.primary)
                        }
                    }
                }
            }
        }
        .navigationTitle(lang["fx.title"])
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            selectedCurrency   = rates.displayCurrency
            showConvertedLocal = rates.showConvertedAmounts
        }
        .onChange(of: selectedCurrency) { _, new in
            // Guard avoids unnecessary re-renders if value didn't change
            guard new != rates.displayCurrency else { return }
            rates.displayCurrency = new
        }
        .task { await rates.refreshIfNeeded() }
    }
}
