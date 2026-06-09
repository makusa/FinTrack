//
//  ExchangeRateWidget.swift
//  FinTrack
//
//  Shows live exchange rates for currency pairs relevant to the user.
//  Pairs are auto-detected from the user's accounts + key pairs for
//  Régis's corridor (XAF, USD, EUR against CAD).
//

import SwiftUI

struct ExchangeRateWidget: View {
    @Environment(LanguageManager.self) private var lang
    @Environment(ExchangeRateManager.self) private var rates
    @Environment(EntitlementManager.self) private var entitlements

    /// Currency codes used in the user's accounts.
    let accountCurrencies: [String]

    // Priority pairs differ by tier
    private var priorityPairs: [(from: String, to: String)] {
        if entitlements.hasPaidTier {
            // Pro: full corridor CAD/XAF/USD/EUR
            return [
                ("CAD", "USD"),
                ("CAD", "EUR"),
                ("CAD", "XAF"),
                ("USD", "XAF"),
            ]
        } else {
            // Courant: CAD and USD only
            return [
                ("CAD", "USD"),
                ("USD", "CAD"),
            ]
        }
    }

    /// Deduplicated pairs: priority first, then account-derived extras.
    private var pairs: [(from: String, to: String)] {
        var seen  = Set<String>()
        var result: [(from: String, to: String)] = []

        func add(_ pair: (from: String, to: String)) {
            let key = "\(pair.from)/\(pair.to)"
            guard !seen.contains(key), pair.from != pair.to else { return }
            seen.insert(key); result.append(pair)
        }

        // Priority corridor pairs first
        for p in priorityPairs { add(p) }

        // Extra pairs from account currencies (Pro only — free tier stays CAD/USD)
        if entitlements.hasPaidTier {
            let display = rates.displayCurrency
            for cur in accountCurrencies where cur != display && cur != "CAD" {
                add((from: "CAD", to: cur))
            }
        }

        return Array(result.prefix(6))   // max 6 rows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text(lang["widget.fx.title"])
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if rates.isLoading {
                    ProgressView().scaleEffect(0.7)
                } else if let updated = rates.lastUpdated {
                    Text(lang.f("fx.updated",
                                updated.appFormattedRelative()))
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

            // Rate rows
            VStack(spacing: 0) {
                ForEach(Array(pairs.enumerated()), id: \.offset) { idx, pair in
                    rateRow(from: pair.from, to: pair.to)
                    if idx < pairs.count - 1 {
                        Divider().padding(.leading, 16)
                    }
                }
            }
            .background(Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
        }
        .task { await rates.refreshIfNeeded() }
    }

    // MARK: - Rate row

    private func rateRow(from: String, to: String) -> some View {
        let rate      = rates.convert(1, from: from, to: to)
        let rateInv   = rates.convert(1, from: to, to: from)
        let fromInfo  = Currencies.info(for: from)
        let toInfo    = Currencies.info(for: to)

        return HStack(spacing: 10) {
            // Currency pair
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(from).font(.callout.weight(.bold))
                    Image(systemName: "arrow.right")
                        .font(.caption2).foregroundStyle(.secondary)
                    Text(to).font(.callout.weight(.bold))
                }
                Text(fromInfo.nameFR.prefix(20) + "")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            Spacer()

            // Rate + inverse
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

// MARK: - Decimal formatting for rates (more decimal places)

private extension Decimal {
    func formattedAsRate(currency: String) -> String {
        let info = Currencies.info(for: currency)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = LanguageManager.shared.locale
        formatter.minimumFractionDigits = currency == "JPY" || currency == "XAF" ? 0 : 4
        formatter.maximumFractionDigits = currency == "JPY" || currency == "XAF" ? 0 : 4
        let str = formatter.string(from: self as NSDecimalNumber) ?? "\(self)"
        return "\(str) \(info.symbol)"
    }
}
