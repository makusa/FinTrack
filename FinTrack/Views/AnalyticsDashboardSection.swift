//
//  AnalyticsDashboardSection.swift
//  FinTrack
//
//  Three analytics cards embedded in the dashboard scroll view:
//   1. BalanceProjectionCard  — 30-day history + 60-day future projection
//   2. IncomeExpenseCard      — 6-month grouped bars
//   3. CategoryBreakdownCard  — current-month expense donut
//
//  Note: Decimal → Double conversions appear here ONLY for chart rendering.
//  All accounting calculations elsewhere remain in Decimal.
//

import SwiftUI
import Charts

// MARK: - Container

struct AnalyticsDashboardSection: View {
    let accounts: [Account]
    let transactions: [Transaction]
    let activeRecurring: [RecurringTransaction]
    let currency: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Analyse & Projection")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            BalanceProjectionCard(
                accounts: accounts,
                transactions: transactions,
                activeRecurring: activeRecurring,
                currency: currency
            )

            IncomeExpenseCard(transactions: transactions, currency: currency)

            CategoryBreakdownCard(transactions: transactions, currency: currency)
        }
    }
}

// MARK: - Decimal display helper (display only, never used for accounting)

private extension Decimal {
    var chartDouble: Double { NSDecimalNumber(decimal: self).doubleValue }
}

// MARK: - 1. Balance Projection Card

struct BalanceProjectionCard: View {
    let accounts: [Account]
    let transactions: [Transaction]
    let activeRecurring: [RecurringTransaction]
    let currency: String

    // MARK: Data point

    private struct Point: Identifiable {
        let id = UUID()
        let date: Date
        let balance: Double
        let isProjected: Bool
    }

    // MARK: Computed data

    private var currentBalance: Decimal {
        accounts
            .filter { $0.currency == currency }
            .reduce(Decimal(0)) { $0 + $1.balance }
    }

    /// Last 30 days of actual balance, reconstructed from transactions.
    private var historicalPoints: [Point] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let start = cal.date(byAdding: .day, value: -30, to: today)!

        let relevant = transactions
            .filter { $0.account?.currency == currency && $0.date >= start }
            .sorted { $0.date < $1.date }

        // Balance at the start of the window = currentBalance minus what happened since
        let windowSum = relevant.reduce(Decimal(0)) { $0 + $1.signedAmount }
        var running = currentBalance - windowSum

        // Group signed amounts by calendar day
        var byDay: [Date: Decimal] = [:]
        for tx in relevant {
            byDay[cal.startOfDay(for: tx.date), default: 0] += tx.signedAmount
        }

        var points: [Point] = []
        var d = start
        while d <= today {
            running += byDay[d, default: 0]
            points.append(Point(date: d, balance: running.chartDouble, isProjected: false))
            d = cal.date(byAdding: .day, value: 1, to: d)!
        }
        return points
    }

    /// Next 60 days projected from recurring transactions.
    private var projectedPoints: [Point] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let horizon = cal.date(byAdding: .day, value: 60, to: today)!

        // Collect all recurring events within the window
        var events: [Date: Decimal] = [:]
        for rule in activeRecurring where rule.account?.currency == currency {
            var d = cal.startOfDay(for: rule.nextDueDate)
            while d <= horizon {
                let signed = rule.type == .income ? rule.amount : -rule.amount
                events[d, default: 0] += signed
                d = cal.startOfDay(for: rule.frequency.nextDate(after: d))
            }
        }

        var running = currentBalance
        // Anchor: today's balance connects historical and projected
        var points: [Point] = [Point(date: today, balance: running.chartDouble, isProjected: true)]

        for day in events.keys.sorted() where day > today {
            running += events[day]!
            points.append(Point(date: day, balance: running.chartDouble, isProjected: true))
        }

        // Horizon anchor so the line extends to the full 60 days
        if let last = points.last, last.date < horizon {
            points.append(Point(date: horizon, balance: last.balance, isProjected: true))
        }
        return points
    }

    private var projectedFinalBalance: Double { projectedPoints.last?.balance ?? currentBalance.chartDouble }
    private var projectedDelta: Double { projectedFinalBalance - currentBalance.chartDouble }

    private var projectedMinBalance: Double {
        projectedPoints.map(\.balance).min() ?? currentBalance.chartDouble
    }
    private var willGoNegative: Bool { projectedMinBalance < 0 }

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // ── Header ──────────────────────────────────────────────────────
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Projection de solde")
                        .font(.subheadline.weight(.semibold))
                    Text("30 derniers jours + 60 jours à venir · \(currency)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Decimal(projectedFinalBalance).formatted(asCurrency: currency))
                        .font(.subheadline.weight(.bold))
                    HStack(spacing: 2) {
                        Image(systemName: projectedDelta >= 0 ? "arrow.up.right" : "arrow.down.right")
                        Text(Decimal(abs(projectedDelta)).formatted(asCurrency: currency))
                    }
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(projectedDelta >= 0 ? .green : .red)
                    Text("dans 60 jours")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // ── Alert if projected balance goes negative ──────────────────
            if willGoNegative {
                Label("Solde projeté négatif sur la période", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.orange)
            }

            // ── Chart ────────────────────────────────────────────────────────
            Chart {
                // Historical area + line
                ForEach(historicalPoints) { p in
                    AreaMark(
                        x: .value("Date", p.date),
                        y: .value("Solde", p.balance)
                    )
                    .foregroundStyle(Color.accentColor.opacity(0.12))
                    .interpolationMethod(.monotone)

                    LineMark(
                        x: .value("Date", p.date),
                        y: .value("Solde", p.balance)
                    )
                    .foregroundStyle(Color.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .interpolationMethod(.monotone)
                }

                // Projected dashed line
                ForEach(projectedPoints) { p in
                    LineMark(
                        x: .value("Date", p.date),
                        y: .value("Solde", p.balance)
                    )
                    .foregroundStyle(Color.teal)
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .interpolationMethod(.stepEnd)
                }

                // Zero baseline (visible when balance could go negative)
                if willGoNegative {
                    RuleMark(y: .value("Zéro", 0))
                        .foregroundStyle(.red.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }

                // Today marker
                RuleMark(x: .value("Aujourd'hui", Calendar.current.startOfDay(for: .now)))
                    .foregroundStyle(.secondary.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, alignment: .center) {
                        Text("Auj.")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 3)
                    }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(Color(.separator).opacity(0.5))
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(compactCurrency(v, currency: currency))
                                .font(.system(size: 9))
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisGridLine().foregroundStyle(Color(.separator).opacity(0.3))
                    AxisValueLabel(
                        format: .dateTime.month(.abbreviated)
                            .locale(Locale(identifier: "fr_CA"))
                    )
                    .font(.system(size: 9))
                }
            }
            .frame(height: 190)

            // ── Legend ───────────────────────────────────────────────────────
            HStack(spacing: 20) {
                HStack(spacing: 5) {
                    Rectangle().fill(Color.accentColor).frame(width: 18, height: 2.5)
                    Text("Réel").font(.caption2).foregroundStyle(.secondary)
                }
                HStack(spacing: 5) {
                    // Dashed line mockup
                    HStack(spacing: 3) {
                        ForEach(0..<3, id: \.self) { _ in
                            Rectangle().fill(Color.teal).frame(width: 5, height: 2)
                        }
                    }
                    Text("Projection").font(.caption2).foregroundStyle(.secondary)
                }
                if willGoNegative {
                    HStack(spacing: 5) {
                        Rectangle().fill(Color.red.opacity(0.5)).frame(width: 12, height: 1.5)
                        Text("Zéro").font(.caption2).foregroundStyle(.red)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
}

// MARK: - 2. Income / Expense Card

struct IncomeExpenseCard: View {
    let transactions: [Transaction]
    let currency: String

    private struct BarData: Identifiable {
        let id = UUID()
        let monthLabel: String
        let kind: String   // "Revenus" | "Dépenses"
        let amount: Double
    }

    private var chartData: (bars: [BarData], labels: [String]) {
        let cal = Calendar.current
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "fr_CA")
        fmt.dateFormat = "MMM"

        var bars: [BarData] = []
        var labels: [String] = []

        for offset in (0...5).reversed() {
            guard
                let anchor = cal.date(byAdding: .month, value: -offset, to: .now),
                let interval = cal.dateInterval(of: .month, for: anchor)
            else { continue }

            let label = fmt.string(from: interval.start).capitalized
            labels.append(label)

            let monthTx = transactions.filter {
                $0.account?.currency == currency &&
                $0.date >= interval.start &&
                $0.date < interval.end
            }
            let income  = monthTx.filter { $0.type == .income  }.reduce(Decimal(0)) { $0 + $1.amount }.chartDouble
            let expense = monthTx.filter { $0.type == .expense }.reduce(Decimal(0)) { $0 + $1.amount }.chartDouble

            bars.append(BarData(monthLabel: label, kind: "Revenus",  amount: income))
            bars.append(BarData(monthLabel: label, kind: "Dépenses", amount: expense))
        }
        return (bars, labels)
    }

    var body: some View {
        let data = chartData
        let hasData = data.bars.contains { $0.amount > 0 }

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Revenus vs Dépenses")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("6 mois · \(currency)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if !hasData {
                emptyPlaceholder("Pas encore de transactions pour afficher les tendances.")
            } else {
                Chart(data.bars) { bar in
                    BarMark(
                        x: .value("Mois", bar.monthLabel),
                        y: .value("Montant", bar.amount)
                    )
                    .foregroundStyle(bar.kind == "Revenus" ? Color.green : Color.red)
                    .position(by: .value("Type", bar.kind))
                    .cornerRadius(4)
                }
                .chartXScale(domain: data.labels)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine().foregroundStyle(Color(.separator).opacity(0.5))
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(compactNumber(v)).font(.system(size: 9))
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks { _ in
                        AxisValueLabel().font(.system(size: 9))
                    }
                }
                .chartLegend(.hidden)
                .frame(height: 160)

                HStack(spacing: 16) {
                    legendDot(.green, "Revenus")
                    legendDot(.red,   "Dépenses")
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
}

// MARK: - 3. Category Breakdown Card

struct CategoryBreakdownCard: View {
    let transactions: [Transaction]
    let currency: String

    private struct Slice: Identifiable {
        let id = UUID()
        let name: String
        let colorHex: String
        let amount: Decimal
        let percent: Double
    }

    private var slices: [Slice] {
        let cal = Calendar.current
        guard let interval = cal.dateInterval(of: .month, for: .now) else { return [] }

        let monthExpenses = transactions.filter {
            $0.type == .expense &&
            $0.account?.currency == currency &&
            $0.date >= interval.start &&
            $0.date < interval.end
        }

        let total = monthExpenses.reduce(Decimal(0)) { $0 + $1.amount }
        guard total > 0 else { return [] }

        // Group by category name
        var grouped: [(name: String, colorHex: String, amount: Decimal)] = []
        var dict: [String: (colorHex: String, amount: Decimal)] = [:]
        var uncategorized: Decimal = 0

        for tx in monthExpenses {
            if let cat = tx.category {
                if dict[cat.name] == nil { dict[cat.name] = (cat.colorHex, 0) }
                dict[cat.name]!.amount += tx.amount
            } else {
                uncategorized += tx.amount
            }
        }

        grouped = dict.map { ($0.key, $0.value.colorHex, $0.value.amount) }
            .sorted { $0.amount > $1.amount }

        var result: [Slice] = []
        var othersTotal: Decimal = uncategorized

        for (i, item) in grouped.enumerated() {
            let pct = ((item.amount / total * 100) as NSDecimalNumber).doubleValue
            if i < 5 {
                result.append(Slice(name: item.name, colorHex: item.colorHex, amount: item.amount, percent: pct))
            } else {
                othersTotal += item.amount
            }
        }

        if othersTotal > 0 {
            let pct = ((othersTotal / total * 100) as NSDecimalNumber).doubleValue
            result.append(Slice(name: "Autres", colorHex: "#8E8E93", amount: othersTotal, percent: pct))
        }

        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Répartition des dépenses")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("Ce mois · \(currency)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if slices.isEmpty {
                emptyPlaceholder("Aucune dépense catégorisée ce mois-ci.")
            } else {
                HStack(alignment: .center, spacing: 20) {
                    // Donut
                    Chart(slices) { slice in
                        SectorMark(
                            angle: .value("Montant", slice.amount.chartDouble),
                            innerRadius: .ratio(0.56),
                            outerRadius: .inset(4)
                        )
                        .foregroundStyle(Color(hex: slice.colorHex))
                        .cornerRadius(3)
                    }
                    .frame(width: 110, height: 110)

                    // Legend
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(slices) { slice in
                            HStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color(hex: slice.colorHex))
                                    .frame(width: 8, height: 8)
                                Text(slice.name)
                                    .font(.caption2)
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                Text(String(format: "%.0f%%", slice.percent))
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(minWidth: 28, alignment: .trailing)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
}

// MARK: - Shared helpers

private func emptyPlaceholder(_ message: String) -> some View {
    Text(message)
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
}

private func legendDot(_ color: Color, _ label: String) -> some View {
    HStack(spacing: 4) {
        Circle().fill(color).frame(width: 8, height: 8)
        Text(label).font(.caption2).foregroundStyle(.secondary)
    }
}

/// Compact currency string for chart Y-axis labels (avoids full formatted strings).
func compactCurrency(_ v: Double, currency: String) -> String {
    let symbol = Currencies.info(for: currency).symbol
    let absV = abs(v)
    if absV >= 1_000_000 { return String(format: "%.1fM %@", v / 1_000_000, symbol) }
    if absV >= 1_000     { return String(format: "%.0fk %@", v / 1_000, symbol) }
    return String(format: "%.0f %@", v, symbol)
}

/// Compact number for bar chart Y-axis.
private func compactNumber(_ v: Double) -> String {
    let absV = abs(v)
    if absV >= 1_000_000 { return String(format: "%.1fM", v / 1_000_000) }
    if absV >= 1_000     { return String(format: "%.0fk", v / 1_000) }
    return String(format: "%.0f", v)
}
