//
//  BudgetDetailView.swift
//  FinTrack
//

import SwiftUI
import SwiftData
import Charts

struct BudgetDetailView: View {
    @Environment(LanguageManager.self) private var lang
    @Bindable var budget: Budget

    @Query(sort: \Transaction.date, order: .reverse)
    private var allTransactions: [Transaction]

    @State private var showEdit = false

    private var status: BudgetStatus {
        BudgetStatus(budget: budget, spent: BudgetCalculator.spent(for: budget, in: allTransactions))
    }

    private var historyData: [Decimal] {
        BudgetCalculator.history(for: budget, in: allTransactions, count: 6)
    }

    /// Transactions in the current period for this budget
    private var periodTransactions: [Transaction] {
        let start = budget.period.periodStart()
        let end   = budget.period.periodEnd()
        return allTransactions.filter { tx in
            guard tx.type == .expense else { return false }
            guard tx.date >= start && tx.date < end else { return false }
            guard tx.account?.currency == budget.currency else { return false }
            if budget.categories.isEmpty { return true }
            guard let txCat = tx.category else { return false }
            return budget.categories.contains { $0.persistentModelID == txCat.persistentModelID }
        }
    }

    var body: some View {
        List {
            // MARK: Progress header
            Section {
                VStack(spacing: 16) {
                    // Icon + name
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color(hex: budget.colorHex).opacity(0.15))
                                .frame(width: 52, height: 52)
                            Image(systemName: budget.iconSystemName)
                                .font(.title2)
                                .foregroundStyle(Color(hex: budget.colorHex))
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(budget.name)
                                .font(.title3.weight(.bold))
                            Text(budget.categoriesLabel)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

                    // Amounts
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(lang["budget.spent"])
                                .font(.caption).foregroundStyle(.secondary)
                            Text(status.spent.formatted(asCurrency: budget.currency))
                                .font(.title2.weight(.bold))
                                .foregroundStyle(status.progressColor)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(status.isOverBudget ? lang["budget.over"] : lang["budget.remaining"])
                                .font(.caption).foregroundStyle(.secondary)
                            Text(status.remaining.magnitude.formatted(asCurrency: budget.currency))
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(status.isOverBudget ? AnyShapeStyle(Color.red) : AnyShapeStyle(.secondary))
                        }
                    }

                    // Progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(.systemGray5)).frame(height: 12)
                            RoundedRectangle(cornerRadius: 6)
                                .fill(status.progressColor)
                                .frame(width: min(geo.size.width * CGFloat(min(status.fraction, 1.0)), geo.size.width), height: 12)
                                .animation(.easeOut(duration: 0.5), value: status.fraction)
                        }
                    }
                    .frame(height: 12)

                    HStack {
                        Text(String(format: "%.1f%%", min(status.fraction * 100, 999)))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(status.progressColor)
                        Spacer()
                        Text("/ \(budget.limitAmount.formatted(asCurrency: budget.currency)) \(budget.period.shortLabel)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(budget.period.currentPeriodLabel())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(.vertical, 6)
            }
            .listRowBackground(Color.clear)

            // MARK: History sparkline
            if historyData.count > 1 {
                Section(lang["budget.history"]) {
                    VStack(alignment: .leading, spacing: 8) {
                        let limitDbl = (budget.limitAmount as NSDecimalNumber).doubleValue
                        let vals     = historyData.map { ($0 as NSDecimalNumber).doubleValue }
                        let maxVal   = max(vals.max() ?? 0, limitDbl) * 1.1

                        Chart {
                            ForEach(Array(vals.enumerated()), id: \.offset) { i, val in
                                BarMark(
                                    x: .value("Period", i),
                                    y: .value(lang["budget.spent"], val)
                                )
                                .foregroundStyle(val > limitDbl ? Color.red.opacity(0.7) : Color(hex: budget.colorHex).opacity(0.7))
                                .cornerRadius(4)
                            }

                            // Limit line
                            RuleMark(y: .value(lang["budget.limit"], limitDbl))
                                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                                .foregroundStyle(Color.red)
                                .annotation(position: .top, alignment: .trailing) {
                                    Text(lang["budget.limit"])
                                        .font(.caption2)
                                        .foregroundStyle(.red)
                                }
                        }
                        .chartYScale(domain: 0...maxVal)
                        .chartXAxis(.hidden)
                        .frame(height: 120)
                    }
                    .padding(.vertical, 4)
                }
            }

            // MARK: Transactions in current period
            Section(lang["budget.period.transactions"]) {
                if periodTransactions.isEmpty {
                    Text(lang["tx.noTx"])
                        .foregroundStyle(.secondary)
                        .font(.callout)
                } else {
                    ForEach(periodTransactions) { tx in
                        NavigationLink {
                            AddEditTransactionView(mode: .edit(tx))
                        } label: {
                            TransactionRow(transaction: tx)
                        }
                    }
                }
            }
        }
        .navigationTitle(budget.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showEdit = true } label: {
                    Image(systemName: "pencil")
                }
            }
        }
        .sheet(isPresented: $showEdit) {
            AddEditBudgetView(mode: .edit(budget))
        }
    }
}
