//
//  CashFlowView.swift
//  FinTrack
//
//  Detailed end-of-month projection: realized so far + still to come,
//  building toward the projected treasury position.
//

import SwiftUI

struct CashFlowView: View {
    @Environment(LanguageManager.self) private var lang
    let summary: CashFlowSummary

    private var approx: String { summary.hasConversion ? "≈ " : "" }

    var body: some View {
        List {
            projectionSection
            realizedSection
            upcomingSection
            if summary.hasConversion { byCurrencySection }
            noteSection
        }
        .navigationTitle(lang["cashflow.projection"])
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Sections

    private var projectionSection: some View {
        Section(lang["cashflow.projection"]) {
            row(lang["cashflow.currentBalance"], summary.currentTreasury)
            row(lang["cashflow.upcomingIn"],  summary.upcomingIncome,  sign: "+", color: .green)
            row(lang["cashflow.upcomingOut"], summary.upcomingExpense, sign: "−")
            HStack {
                Text(lang["cashflow.projectedBalance"]).font(.subheadline.weight(.semibold))
                Spacer()
                Text(approx + summary.projectedEndBalance.formatted(asCurrency: summary.displayCurrency))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(summary.projectedEndBalance >= 0 ? .green : .red)
            }
        }
    }

    private var realizedSection: some View {
        Section(lang["cashflow.section.realized"]) {
            row(lang["cashflow.inflows"],  summary.realizedIncome,  sign: "+", color: .green)
            row(lang["cashflow.outflows"], summary.realizedExpense, sign: "−")
            row(lang["cashflow.netResult"], summary.realizedNet,
                color: summary.realizedNet >= 0 ? .green : .red)
        }
    }

    private var upcomingSection: some View {
        Section(lang["cashflow.section.upcoming"]) {
            row(lang["cashflow.inflows"],  summary.upcomingIncome,  sign: "+", color: .green)
            row(lang["cashflow.outflows"], summary.upcomingExpense, sign: "−")
            row(lang["cashflow.netResult"], summary.upcomingNet,
                color: summary.upcomingNet >= 0 ? .green : .red)
        }
    }

    private var byCurrencySection: some View {
        Section(lang["cashflow.byCurrency"]) {
            ForEach(summary.byCurrency.filter { $0.hasUpcoming }) { r in
                HStack {
                    Text(r.currency).font(.subheadline.weight(.medium))
                    Spacer()
                    Text("+\(r.upcomingIncome.formatted(asCurrency: r.currency))")
                        .font(.caption).foregroundStyle(.green)
                    Text("−\(r.upcomingExpense.formatted(asCurrency: r.currency))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var noteSection: some View {
        Section {
            Text(lang["cashflow.note2"])
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helper

    private func row(_ label: String, _ amount: Decimal,
                     sign: String? = nil, color: Color = .primary) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text((sign ?? "") + amount.formatted(asCurrency: summary.displayCurrency))
                .foregroundStyle(color)
        }
    }
}
