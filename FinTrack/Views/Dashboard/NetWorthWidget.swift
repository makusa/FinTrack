//
//  NetWorthWidget.swift
//  FinTrack
//
//  Displays: total assets (accounts) − total liabilities (loans + credit lines)
//  = net worth, with a visual asset/liability breakdown.
//

import SwiftUI
import SwiftData
import Charts

struct NetWorthWidget: View {
    @Environment(LanguageManager.self) private var lang
    @Environment(ExchangeRateManager.self) private var rates

    // Data passed from parent (already queried)
    let accounts: [(currency: String, total: Decimal)]
    let loans: [Loan]
    let creditLines: [CreditLine]

    private let display: String

    init(accounts: [(currency: String, total: Decimal)],
         loans: [Loan],
         creditLines: [CreditLine]) {
        self.accounts    = accounts
        self.loans       = loans
        self.creditLines = creditLines
        self.display     = ExchangeRateManager.shared.displayCurrency
    }

    // MARK: Computed

    private var totalAssets: Decimal {
        accounts.reduce(Decimal(0)) { sum, row in
            sum + ExchangeRateManager.shared.convert(
                max(row.total, 0), from: row.currency, to: display)
        }
    }

    private var totalLoanDebt: Decimal {
        loans.reduce(Decimal(0)) { sum, loan in
            let bal = Decimal(loan.calculator.currentBalance)
            return sum + ExchangeRateManager.shared.convert(bal, from: loan.currency, to: display)
        }
    }

    private var totalCLDebt: Decimal {
        creditLines.reduce(Decimal(0)) { sum, cl in
            sum + ExchangeRateManager.shared.convert(cl.currentBalance, from: cl.currency, to: display)
        }
    }

    private var totalLiabilities: Decimal { totalLoanDebt + totalCLDebt }
    private var netWorth: Decimal         { totalAssets - totalLiabilities }

    private var debtRatio: Double {
        guard totalAssets > 0 else { return 0 }
        let ratio = (totalLiabilities as NSDecimalNumber).doubleValue
                  / (totalAssets       as NSDecimalNumber).doubleValue
        return min(ratio, 1.0)
    }

    private var ratioColor: Color {
        switch debtRatio {
        case ..<0.30: return .green
        case ..<0.60: return .orange
        default:      return .red
        }
    }

    // MARK: View

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text(lang["widget.netWorth.title"])
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(lang["widget.netWorth.subtitle"])
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            // Card
            VStack(alignment: .leading, spacing: 14) {

                // Net worth big number
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(netWorth.formatted(asCurrency: display))
                        .font(.title.weight(.bold))
                        .foregroundStyle(netWorth >= 0 ? Color.primary : Color.red)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Spacer()
                    // Debt ratio badge
                    if totalLiabilities > 0 {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(String(format: "%.0f%%", debtRatio * 100))
                                .font(.callout.weight(.bold))
                                .foregroundStyle(ratioColor)
                            Text(lang["widget.netWorth.debtRatio"])
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Stacked bar: assets vs liabilities
                if totalAssets > 0 || totalLiabilities > 0 {
                    GeometryReader { geo in
                        let total = (totalAssets + totalLiabilities as NSDecimalNumber).doubleValue
                        let assetW = total > 0
                            ? geo.size.width * CGFloat((totalAssets as NSDecimalNumber).doubleValue / total)
                            : 0
                        HStack(spacing: 2) {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color.green)
                                .frame(width: max(assetW, 4), height: 10)
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color.red.opacity(0.75))
                                .frame(width: max(geo.size.width - assetW - 2, 4), height: 10)
                        }
                    }
                    .frame(height: 10)
                }

                Divider()

                // Row breakdown
                Group {
                    netWorthRow(
                        icon: "building.columns.fill",
                        color: .green,
                        label: lang["widget.netWorth.assets"],
                        value: totalAssets,
                        positive: true
                    )
                    if totalLoanDebt > 0 {
                        netWorthRow(
                            icon: "banknote.fill",
                            color: .red,
                            label: lang["loan.title"],
                            value: totalLoanDebt,
                            positive: false
                        )
                    }
                    if totalCLDebt > 0 {
                        netWorthRow(
                            icon: "creditcard.fill",
                            color: .orange,
                            label: lang["cl.title"],
                            value: totalCLDebt,
                            positive: false
                        )
                    }
                }
            }
            .padding(16)
            .background(Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
        }
    }

    private func netWorthRow(icon: String, color: Color,
                              label: String, value: Decimal,
                              positive: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 20)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text((positive ? "" : "−") + value.formatted(asCurrency: display))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(positive ? .green : .red)
        }
    }
}
