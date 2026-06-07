//
//  CashFlowView.swift
//  FinTrack
//

import SwiftUI

struct CashFlowView: View {
    @Environment(LanguageManager.self) private var lang

    let summary: CashFlowSummary

    var body: some View {
        List {
            // ── Income ──────────────────────────────────────────────────────
            if !summary.incomeLines.isEmpty {
                Section {
                    ForEach(summary.incomeLines) { line in
                        amountRow(label: line.label, sublabel: line.sublabel,
                                  amount: line.amount, currency: summary.currency,
                                  color: .green, sign: "+")
                    }
                    totalRow(label: lang["cashflow.totalIncome"], amount: summary.monthlyIncome,
                             currency: summary.currency, color: .green)
                } header: {
                    Label(lang["cashflow.monthlyIncome"], systemImage: "arrow.down.left.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            // ── Expenses ─────────────────────────────────────────────────────
            if !summary.expenseLines.isEmpty {
                Section {
                    ForEach(summary.expenseLines) { line in
                        amountRow(label: line.label, sublabel: line.sublabel,
                                  amount: line.amount, currency: summary.currency,
                                  color: .primary, sign: "−")
                    }
                    totalRow(label: lang["cashflow.totalExp"], amount: summary.monthlyExpenses,
                             currency: summary.currency, color: .red)
                } header: {
                    Label(lang["cashflow.recurringExp"], systemImage: "arrow.up.right.circle.fill")
                        .foregroundStyle(.red)
                }
            }

            // ── Loans ────────────────────────────────────────────────────────
            if !summary.loanLines.isEmpty {
                Section {
                    ForEach(summary.loanLines) { line in
                        amountRow(label: line.label, sublabel: line.sublabel,
                                  amount: line.amount, currency: summary.currency,
                                  color: .primary, sign: "−")
                    }
                    totalRow(label: lang["cashflow.totalLoans"], amount: summary.monthlyLoanPayments,
                             currency: summary.currency, color: .orange)
                } header: {
                    Label(lang["cashflow.loanPayments"], systemImage: "house.fill")
                        .foregroundStyle(.orange)
                }
            }

            // ── Credit lines ─────────────────────────────────────────────────
            if !summary.creditLineLines.isEmpty {
                Section {
                    ForEach(summary.creditLineLines) { line in
                        amountRow(label: line.label, sublabel: line.sublabel,
                                  amount: line.amount, currency: summary.currency,
                                  color: .primary, sign: "−")
                    }
                    totalRow(label: lang["cashflow.totalCL"], amount: summary.monthlyCreditLinePayments,
                             currency: summary.currency, color: .red)
                } header: {
                    Label(lang["cashflow.clPayments"], systemImage: "creditcard.fill")
                        .foregroundStyle(.red)
                }
            }

            // ── Net surplus ──────────────────────────────────────────────────
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lang["cashflow.surplus"])
                            .font(.headline)
                        Text(lang["cashflow.surplus.before"])
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(summary.monthlySurplus.formatted(asCurrency: summary.currency))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(summary.isPositive ? .green : .red)
                }
                .padding(.vertical, 4)

                if !summary.isPositive {
                    Label(lang["cashflow.warning.deficit"],
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } header: {
                Label(lang["cashflow.netResult"], systemImage: "equal.circle.fill")
            }

            // ── Project allocations ──────────────────────────────────────────
            if !summary.projectLines.isEmpty {
                Section {
                    ForEach(summary.projectLines) { line in
                        amountRow(label: line.label, sublabel: line.sublabel,
                                  amount: line.amount, currency: summary.currency,
                                  color: .primary, sign: "−")
                    }
                    Divider()
                    HStack {
                        Text(lang["cashflow.free"])
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(summary.monthlyFree.formatted(asCurrency: summary.currency))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(summary.isCovered ? .green : .red)
                    }
                    if !summary.isCovered {
                        Label(lang["cashflow.warning.overAllocated"],
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Label(lang["cashflow.allocation"], systemImage: "target")
                }
            }

            // ── Note ─────────────────────────────────────────────────────────
            Section {
                Text(lang["cashflow.note"])
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(lang["cashflow.title"])
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Row builders

    private func amountRow(label: String, sublabel: String?,
                           amount: Decimal, currency: String,
                           color: Color, sign: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.callout).lineLimit(1)
                if let sub = sublabel {
                    Text(sub).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text("\(sign) \(amount.formatted(asCurrency: currency))")
                .font(.callout.weight(.medium))
                .foregroundStyle(color)
        }
    }

    private func totalRow(label: String, amount: Decimal,
                          currency: String, color: Color) -> some View {
        HStack {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text(amount.formatted(asCurrency: currency))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(color)
        }
    }
}
