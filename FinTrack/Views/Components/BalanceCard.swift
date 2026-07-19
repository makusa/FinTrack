//
//  BalanceCard.swift
//  FinTrack
//

import SwiftUI

struct BalanceCard: View {
    let account: Account
    @Environment(ExchangeRateManager.self) private var rates

    /// Cached gradient derived from colorHex — avoids inline recreation on every render.
    private var cardGradient: LinearGradient {
        let base = Color(hex: account.colorHex)
        return LinearGradient(
            colors: [base, base.opacity(0.7)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var cardShadowColor: Color { Color(hex: account.colorHex).opacity(0.25) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if account.iconSystemName.isEmpty, let domain = account.bankDomain {
                    BankLogoView(domain: domain, size: 32, cornerRadius: 8)
                } else if account.iconSystemName.isEmpty {
                    Image(systemName: account.type.defaultIconSystemName)
                        .font(.title2)
                        .foregroundStyle(ColorPalette.foregroundColor(on: account.colorHex))
                } else {
                    Image(systemName: account.iconSystemName)
                        .font(.title2)
                        .foregroundStyle(ColorPalette.foregroundColor(on: account.colorHex))
                }
                Spacer()
                Text(account.currency)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.white.opacity(0.2), in: Capsule())
                    .foregroundStyle(.white)
            }
            .padding(.top, 4)

            Spacer(minLength: 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                Text(account.institution)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
            }

            Text(account.balance.formatted(asCurrency: account.currency))
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            if account.currency != rates.displayCurrency,
               rates.showConvertedAmounts,
               let converted = rates.convertedLabel(account.balance, from: account.currency, to: rates.displayCurrency) {
                Text(converted)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(width: 200, height: 140)
        .background(cardGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: cardShadowColor, radius: 8, x: 0, y: 4)
    }
}
