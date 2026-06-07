//
//  ExchangeRateSettingsView.swift
//  FinTrack
//

import SwiftUI

struct ExchangeRateSettingsView: View {
    @Environment(LanguageManager.self) private var lang
    @Environment(ExchangeRateManager.self) private var rates

    var body: some View {
        List {
            // MARK: Display currency
            Section {
                Picker(lang["fx.displayCurrency"], selection: Binding(
                    get: { rates.displayCurrency },
                    set: { rates.displayCurrency = $0 }
                )) {
                    ForEach(Currencies.all) { c in
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

                Toggle(lang["fx.showConverted"], isOn: Binding(
                    get: { rates.showConvertedAmounts },
                    set: { rates.showConvertedAmounts = $0 }
                ))
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
                        Text(updated.formatted(date: .abbreviated, time: .shortened))
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
                    ForEach(Currencies.all.filter { $0.code != rates.baseCurrency }, id: \.code) { currency in
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
        .task { await rates.refreshIfNeeded() }
    }
}
