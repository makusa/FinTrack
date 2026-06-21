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
    @State private var showAddCurrency = false
    @State private var showPaywall = false

    /// Free tier may track up to freeMaxCurrencies; Pro is unlimited.
    private var canAddCurrency: Bool {
        entitlements.hasPaidTier || rates.activeCurrencies.count < FinTrackLimit.freeMaxCurrencies
    }

    private var hasNonBaseActive: Bool {
        rates.activeCurrencies.contains { $0 != rates.baseCurrency }
    }

    var body: some View {
        List {
            // MARK: My currencies (user-managed list)
            Section {
                ForEach(rates.activeCurrencyInfos) { c in
                    HStack {
                        Text(c.symbol)
                            .frame(width: 44, alignment: .leading)
                            .foregroundStyle(.secondary)
                        Text(c.code + " — " + c.nameFR)
                        Spacer()
                        if c.code == ExchangeRateManager.pinnedCurrency {
                            Image(systemName: "pin.fill")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .onDelete(perform: removeCurrencies)

                Button {
                    if canAddCurrency { showAddCurrency = true } else { showPaywall = true }
                } label: {
                    Label(lang["fx.currencies.add"],
                          systemImage: canAddCurrency ? "plus.circle" : "lock.fill")
                }
            } header: {
                Text(lang["fx.currencies.section"])
            } footer: {
                Text(canAddCurrency ? lang["fx.currencies.footer"] : lang["fx.currencies.freeCap"])
            }

            // MARK: Display currency
            Section {
                Picker(lang["fx.displayCurrency"], selection: $selectedCurrency) {
                    ForEach(rates.activeCurrencyInfos) { c in
                        HStack {
                            Text(c.symbol)
                                .frame(width: 40, alignment: .leading)
                                .foregroundStyle(.secondary)
                            Text(c.code + " — " + c.nameFR)
                        }
                        .tag(c.code)
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

            // MARK: Current rates (tracked currencies)
            if !rates.rates.isEmpty && hasNonBaseActive {
                Section(lang["fx.rates.current"]) {
                    let display = rates.displayCurrency
                    ForEach(rates.activeCurrencyInfos.filter { $0.code != rates.baseCurrency }) { currency in
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
        .sheet(isPresented: $showAddCurrency) {
            AddCurrencySheet()
        }
        .sheet(isPresented: $showPaywall) {
            NavigationStack {
                ProGateView(feature: .exchangeRates)
                    .environment(entitlements)
            }
        }
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

    private func removeCurrencies(at offsets: IndexSet) {
        let infos = rates.activeCurrencyInfos
        for i in offsets {
            let code = infos[i].code
            if rates.canRemove(code) { rates.removeCurrency(code) }
        }
    }
}

// MARK: - Add-currency catalogue picker

private struct AddCurrencySheet: View {
    @Environment(LanguageManager.self) private var lang
    @Environment(ExchangeRateManager.self) private var rates
    @Environment(\.dismiss) private var dismiss

    @State private var search = ""

    /// Catalogue currencies not already tracked, filtered by the search text.
    private var available: [CurrencyInfo] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return Currencies.all.filter { c in
            !rates.activeCurrencies.contains(c.code)
                && (q.isEmpty
                    || c.code.lowercased().contains(q)
                    || c.nameFR.lowercased().contains(q))
        }
    }

    var body: some View {
        NavigationStack {
            List(available) { c in
                Button {
                    rates.addCurrency(c.code)
                    dismiss()
                } label: {
                    HStack {
                        Text(c.symbol)
                            .frame(width: 44, alignment: .leading)
                            .foregroundStyle(.secondary)
                        Text(c.code + " — " + c.nameFR)
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "plus.circle")
                            .foregroundStyle(.tint)
                    }
                }
            }
            .searchable(text: $search, prompt: lang["fx.currencies.searchPrompt"])
            .navigationTitle(lang["fx.currencies.add"])
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(lang["action.cancel"]) { dismiss() }
                }
            }
        }
    }
}
