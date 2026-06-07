//
//  BalanceCard.swift
//  FinTrack
//

import SwiftUI

struct BalanceCard: View {
    let account: Account
    @Environment(ExchangeRateManager.self) private var rates

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
               let converted = rates.convertedLabel(account.balance, from: account.currency, to: rates.displayCurrency) {
                Text(converted)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(16)
        .frame(width: 200, height: 140)
        .background(
            LinearGradient(
                colors: [Color(hex: account.colorHex), Color(hex: account.colorHex).opacity(0.7)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .shadow(color: Color(hex: account.colorHex).opacity(0.25), radius: 8, x: 0, y: 4)
    }
}
