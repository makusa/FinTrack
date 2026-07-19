//
//  ExchangeRateWidget.swift
//  FinTrack
//
//  Live exchange rates between the user's chosen display currency and each
//  currency they track in Settings. Available to all tiers; the rows are
//  driven entirely by the tracked-currency list (rates.activeCurrencies),
//  and every rate is expressed relative to the display currency.
//

import SwiftUI

struct ExchangeRateWidget: View {
    @Environment(LanguageManager.self) private var lang
    @Environment(ExchangeRateManager.self) private var rates

    /// Tracked currencies (managed in Settings), minus the display currency
    /// itself — each row shows 1 displayCurrency = X targetCurrency.
    private var targetCurrencies: [String] {
        rates.activeCurrencies.filter { $0 != rates.displayCurrency }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(lang["widget.fx.title"])
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if rates.isLoading {
                    ProgressView().scaleEffect(0.7)
                } else if let updated = rates.lastUpdated {
                    Text(lang.f("fx.updated", updated.appFormattedRelative()))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Button {
                    Task { await rates.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                        .foregroundStyle(.tint)
                }
            }
            .padding(.horizontal)

            if targetCurrencies.isEmpty {
                Text(lang["widget.fx.empty"])
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20).padding(.horizontal)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(targetCurrencies.enumerated()), id: \.offset) { idx, cur in
                        rateRow(to: cur)
                        if idx < targetCurrencies.count - 1 {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
                .background(Color(.secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
            }
        }
        .task { await rates.refreshIfNeeded() }
    }

    // MARK: - Rate row (1 displayCurrency = X target, plus inverse)

    private func rateRow(to: String) -> some View {
        let from      = rates.displayCurrency
        let rate      = rates.convert(1, from: from, to: to)
        let rateInv   = rates.convert(1, from: to, to: from)
        let fromInfo  = Currencies.info(for: from)
        let toInfo    = Currencies.info(for: to)

        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(from).font(.callout.weight(.bold))
                    Image(systemName: "arrow.right")
                        .font(.caption2).foregroundStyle(.secondary)
                    Text(to).font(.callout.weight(.bold))
                }
                Text(toInfo.name.prefix(24) + "")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if rates.rates.isEmpty {
                    Text(lang["fx.unavailable"])
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("1 \(fromInfo.symbol) = \(rate.formatted(asCurrency: to))")
                        .font(.callout.weight(.semibold))
                    Text("1 \(toInfo.symbol) = \(rateInv.formatted(asCurrency: from))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}
