//
//  TransactionRow.swift
//  FinTrack
//

import SwiftUI

struct TransactionRow: View {
    let transaction: Transaction

    private var iconName: String {
        transaction.category?.iconSystemName ?? "circle.dashed"
    }

    private var iconColor: Color {
        if let hex = transaction.category?.colorHex {
            return Color(hex: hex)
        }
        return .gray
    }

    private var primaryText: String {
        if let payee = transaction.payee, !payee.isEmpty {
            return payee
        }
        if let cat = transaction.category {
            return cat.name
        }
        return transaction.type == .income ? "Revenu" : "Dépense"
    }

    private var secondaryText: String {
        var parts: [String] = []
        if let acc = transaction.account {
            parts.append(acc.name)
        }
        if let cat = transaction.category, transaction.payee != nil {
            parts.append(cat.name)
        }
        return parts.joined(separator: " · ")
    }

    private var amountText: String {
        let code = transaction.account?.currency ?? Currencies.default
        let prefix = transaction.type == .income ? "+" : "−"
        return prefix + transaction.amount.formatted(asCurrency: code)
    }

    private var amountColor: Color {
        transaction.type == .income ? .green : .primary
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: iconName)
                    .foregroundStyle(iconColor)
                    .font(.system(size: 17, weight: .semibold))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(primaryText)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                if !secondaryText.isEmpty {
                    Text(secondaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(amountText)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(amountColor)
                Text(transaction.date.formatted(.dateTime.day().month(.abbreviated)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
