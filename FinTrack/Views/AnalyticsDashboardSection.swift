//
//  AnalyticsDashboardSection.swift
//  FinTrack
//
//  Three analytics cards in the dashboard scroll view:
//   1. BalanceProjectionCard  — interactive scrubber + selectable time range (3m → 3a)
//   2. IncomeExpenseCard      — selectable window (3m / 6m / 1a)
//   3. CategoryBreakdownCard  — current-month expense donut
//
//  Decimal → Double only for chart rendering. All accounting stays in Decimal.
//

import SwiftUI
import Charts

// MARK: - Decimal display helper (display only)
private extension Decimal {
    var chartDouble: Double { NSDecimalNumber(decimal: self).doubleValue }
}

// MARK: - Container
struct AnalyticsDashboardSection: View {
    let accounts: [Account]
    let transactions: [Transaction]
    let activeRecurring: [RecurringTransaction]
    let currency: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(lang["analytics.title"])
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

// MARK: - Shared time range picker

private struct RangePill: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    isSelected ? Color.accentColor : Color(.tertiarySystemBackground),
                    in: Capsule()
                )
                .foregroundStyle(isSelected ? .white : .secondary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 1. Balance Projection Card ─────────────────────────────────────────

struct BalanceProjectionCard: View {
    let accounts: [Account]
    let transactions: [Transaction]
    let activeRecurring: [RecurringTransaction]
    let currency: String

    // MARK: Time range
    enum Range: String, CaseIterable {
        case threeMonths = "3m"
        case sixMonths   = "6m"
        case oneYear     = "1a"
        case twoYears    = "2a"
        case threeYears  = "3a"

        var projectionDays: Int {
            switch self {
            case .threeMonths: return 90
            case .sixMonths:   return 180
            case .oneYear:     return 365
            case .twoYears:    return 730
            case .threeYears:  return 1_095
            }
        }
        var historyDays: Int {
            switch self {
            case .threeMonths: return 30
            case .sixMonths:   return 60
            case .oneYear:     return 90
            case .twoYears:    return 180
            case .threeYears:  return 365
            }
        }
        var xStride: Calendar.Component { self == .threeMonths ? .month : .month }
        var xStrideValue: Int {
            switch self {
            case .threeMonths: return 1
            case .sixMonths:   return 1
            case .oneYear:     return 2
            case .twoYears:    return 4
            case .threeYears:  return 6
            }
        }
    }

    // MARK: Data point
    struct Point: Identifiable {
        let id = UUID()
        let date: Date
        let balance: Double
        let isProjected: Bool
    }

    // MARK: State
    @State private var selectedRange: Range = .threeMonths
    @State private var selectedDate: Date?  = nil
    @State private var selectedBalance: Double? = nil

    // MARK: Current balance
    private var currentBalance: Decimal {
        accounts.filter { $0.currency == currency }
                .reduce(Decimal(0)) { $0 + $1.balance }
    }

    // MARK: Historical points
    private func historicalPoints(historyDays: Int) -> [Point] {
        let cal   = Calendar.current
        let today = cal.startOfDay(for: .now)
        let start = cal.date(byAdding: .day, value: -historyDays, to: today)!

        let relevant = transactions
            .filter { $0.account?.currency == currency && $0.date >= start }
            .sorted { $0.date < $1.date }

        let windowSum = relevant.reduce(Decimal(0)) { $0 + $1.signedAmount }
        var running   = currentBalance - windowSum

        var byDay: [Date: Decimal] = [:]
        for tx in relevant {
            byDay[cal.startOfDay(for: tx.date), default: 0] += tx.signedAmount
        }

        var pts: [Point] = []
        var d = start
        while d <= today {
            running += byDay[d, default: 0]
            pts.append(Point(date: d, balance: running.chartDouble, isProjected: false))
            d = cal.date(byAdding: .day, value: 1, to: d)!
        }
        return pts
    }

    // MARK: Projected points
    private func projectedPoints(days: Int) -> [Point] {
        let cal     = Calendar.current
        let today   = cal.startOfDay(for: .now)
        let horizon = cal.date(byAdding: .day, value: days, to: today)!

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
        var pts: [Point] = [Point(date: today, balance: running.chartDouble, isProjected: true)]

        for day in events.keys.sorted() where day > today {
            running += events[day]!
            pts.append(Point(date: day, balance: running.chartDouble, isProjected: true))
        }
        if let last = pts.last, last.date < horizon {
            pts.append(Point(date: horizon, balance: last.balance, isProjected: true))
        }
        return pts
    }

    // MARK: Interpolation
    /// Returns the balance at `date` by linear interpolation between surrounding points.
    private func interpolatedBalance(at date: Date, historical: [Point], projected: [Point]) -> Double? {
        let all = (historical + projected).sorted { $0.date < $1.date }
        guard !all.isEmpty else { return nil }
        if date <= all.first!.date { return all.first!.balance }
        if date >= all.last!.date  { return all.last!.balance }
        for i in 0..<all.count - 1 {
            let a = all[i]; let b = all[i + 1]
            if a.date <= date && date <= b.date {
                let span = b.date.timeIntervalSince(a.date)
                guard span > 0 else { return a.balance }
                let ratio = date.timeIntervalSince(a.date) / span
                return a.balance + ratio * (b.balance - a.balance)
            }
        }
        return all.last!.balance
    }

    // MARK: Body
    var body: some View {
        let hist = historicalPoints(historyDays: selectedRange.historyDays)
        let proj = projectedPoints(days: selectedRange.projectionDays)
        let endBalance   = proj.last?.balance ?? currentBalance.chartDouble
        let delta        = endBalance - currentBalance.chartDouble
        let minBalance   = (hist + proj).map(\.balance).min() ?? 0
        let willNegative = minBalance < 0

        VStack(alignment: .leading, spacing: 10) {

            // ── Header ─────────────────────────────────────────────────────
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(lang["analytics.balanceProjection"])
                        .font(.subheadline.weight(.semibold))
                    Text(currency)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                // Scrubber readout OR end-of-range summary
                if let date = selectedDate, let bal = selectedBalance {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Decimal(bal).formatted(asCurrency: currency))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(date > .now ? .teal : .accentColor)
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .trailing)))
                } else {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Decimal(endBalance).formatted(asCurrency: currency))
                            .font(.subheadline.weight(.bold))
                        HStack(spacing: 3) {
                            Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                            Text(Decimal(abs(delta)).formatted(asCurrency: currency))
                        }
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(delta >= 0 ? .green : .red)
                        Text("dans \(selectedRange.rawValue)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: selectedDate != nil)

            // ── Range picker ───────────────────────────────────────────────
            HStack(spacing: 6) {
                ForEach(Range.allCases, id: \.self) { r in
                    RangePill(label: r.rawValue, isSelected: selectedRange == r) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedRange = r
                            selectedDate   = nil
                            selectedBalance = nil
                        }
                    }
                }
            }

            if willNegative {
                Label("Solde projeté négatif sur la période",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.orange)
            }

            // ── Chart ──────────────────────────────────────────────────────
            Chart {
                // Historical area + line
                ForEach(hist) { p in
                    AreaMark(x: .value("Date", p.date), y: .value("Solde", p.balance))
                        .foregroundStyle(Color.accentColor.opacity(0.12))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Date", p.date), y: .value("Solde", p.balance))
                        .foregroundStyle(Color.accentColor)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                        .interpolationMethod(.monotone)
                }

                // Projected dashed line
                ForEach(proj) { p in
                    LineMark(x: .value("Date", p.date), y: .value("Solde", p.balance))
                        .foregroundStyle(Color.teal)
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [6, 4]))
                        .interpolationMethod(.stepEnd)
                }

                // Zero baseline
                if willNegative {
                    RuleMark(y: .value(lang["analytics.zero"], 0))
                        .foregroundStyle(.red.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }

                // Today marker
                RuleMark(x: .value(lang["analytics.todayShort"], Calendar.current.startOfDay(for: .now)))
                    .foregroundStyle(.secondary.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, alignment: .center) {
                        Text(lang["analytics.todayShort"])
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }

                // Scrubber rule
                if let date = selectedDate {
                    RuleMark(x: .value("Sélection", date))
                        .foregroundStyle(Color.primary.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                    if let bal = selectedBalance {
                        PointMark(x: .value("Date", date), y: .value("Solde", bal))
                            .symbolSize(60)
                            .foregroundStyle(date > .now ? Color.teal : Color.accentColor)
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(Color(.separator).opacity(0.5))
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(compactCurrency(v, currency: currency)).font(.system(size: 9))
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: selectedRange.xStride,
                                          count: selectedRange.xStrideValue)) { _ in
                    AxisGridLine().foregroundStyle(Color(.separator).opacity(0.3))
                    AxisValueLabel(
                        format: .dateTime.month(.abbreviated)
                            .locale(Locale(identifier: "fr_CA"))
                    ).font(.system(size: 9))
                }
            }
            .frame(height: 200)
            .contentShape(Rectangle())
            // ── Interactive overlay ────────────────────────────────────────
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { val in
                                    guard let plotFrame = proxy.plotFrame else { return }
                                    let origin = geo[plotFrame].origin
                                    let x = val.location.x - origin.x
                                    guard x >= 0 else { return }
                                    if let date: Date = proxy.value(atX: x) {
                                        let snapped = Calendar.current.startOfDay(for: date)
                                        selectedDate = snapped
                                        selectedBalance = interpolatedBalance(
                                            at: snapped,
                                            historical: hist,
                                            projected: proj
                                        )
                                    }
                                }
                                .onEnded { _ in
                                    withAnimation(.easeOut(duration: 0.4)) {
                                        selectedDate    = nil
                                        selectedBalance = nil
                                    }
                                }
                        )
                }
            }

            // ── Legend ─────────────────────────────────────────────────────
            HStack(spacing: 16) {
                HStack(spacing: 5) {
                    Rectangle().fill(Color.accentColor).frame(width: 16, height: 2.5)
                    Text(lang["analytics.real"]).font(.caption2).foregroundStyle(.secondary)
                }
                HStack(spacing: 5) {
                    HStack(spacing: 3) {
                        ForEach(0..<3, id: \.self) { _ in
                            Rectangle().fill(Color.teal).frame(width: 5, height: 2)
                        }
                    }
                    Text(lang["analytics.projection"]).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Text(lang["analytics.scrubHint"])
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
}

// MARK: - 2. Income / Expense Card ────────────────────────────────────────────

struct IncomeExpenseCard: View {
    let transactions: [Transaction]
    let currency: String

    enum Window: String, CaseIterable {
        case threeMonths = "3m"
        case sixMonths   = "6m"
        case oneYear     = "1a"
        var monthCount: Int {
            switch self { case .threeMonths: return 3; case .sixMonths: return 6; case .oneYear: return 12 }
        }
    }

    struct BarData: Identifiable {
        let id = UUID()
        let monthLabel: String
        let monthDate: Date
        let kind: String
        let amount: Double
    }

    struct MonthSummary: Identifiable {
        let id = UUID()
        let label: String
        let date: Date
        let income: Double
        let expense: Double
        var net: Double { income - expense }
    }

    @State private var selectedWindow: Window = .sixMonths
    @State private var selectedMonth: MonthSummary? = nil

    private func buildData() -> (bars: [BarData], summaries: [MonthSummary], labels: [String]) {
        let cal = Calendar.current
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "fr_CA")
        fmt.dateFormat = "MMM"

        var bars: [BarData] = []
        var summaries: [MonthSummary] = []
        var labels: [String] = []

        let count = selectedWindow.monthCount
        for offset in (0..<count).reversed() {
            guard let anchor   = cal.date(byAdding: .month, value: -offset, to: .now),
                  let interval = cal.dateInterval(of: .month, for: anchor) else { continue }

            let label = fmt.string(from: interval.start).capitalized
            labels.append(label)

            let monthTx = transactions.filter {
                $0.account?.currency == currency &&
                $0.date >= interval.start && $0.date < interval.end
            }
            let income  = monthTx.filter { $0.type == .income  }.reduce(Decimal(0)) { $0 + $1.amount }.chartDouble
            let expense = monthTx.filter { $0.type == .expense }.reduce(Decimal(0)) { $0 + $1.amount }.chartDouble

            bars.append(BarData(monthLabel: label, monthDate: interval.start, kind: "Revenus",  amount: income))
            bars.append(BarData(monthLabel: label, monthDate: interval.start, kind: "Dépenses", amount: expense))
            summaries.append(MonthSummary(label: label, date: interval.start, income: income, expense: expense))
        }
        return (bars, summaries, labels)
    }

    var body: some View {
        let data = buildData()
        let hasData = data.bars.contains { $0.amount > 0 }

        VStack(alignment: .leading, spacing: 10) {
            // ── Header ─────────────────────────────────────────────────────
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(lang["analytics.incomeExpense"])
                        .font(.subheadline.weight(.semibold))
                    Text(currency)
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                // Readout for selected month
                if let sel = selectedMonth {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(sel.label.capitalized)
                            .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            HStack(spacing: 3) {
                                Circle().fill(.green).frame(width: 6, height: 6)
                                Text(Decimal(sel.income).formatted(asCurrency: currency))
                            }
                            HStack(spacing: 3) {
                                Circle().fill(.red).frame(width: 6, height: 6)
                                Text(Decimal(sel.expense).formatted(asCurrency: currency))
                            }
                        }
                        .font(.caption2)
                        Text(sel.net >= 0 ? "+\(Decimal(sel.net).formatted(asCurrency: currency))" : Decimal(sel.net).formatted(asCurrency: currency))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(sel.net >= 0 ? .green : .red)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .trailing)))
                }
            }
            .animation(.easeInOut(duration: 0.15), value: selectedMonth?.id)

            // ── Range picker ───────────────────────────────────────────────
            HStack(spacing: 6) {
                ForEach(Window.allCases, id: \.self) { w in
                    RangePill(label: w.rawValue, isSelected: selectedWindow == w) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedWindow = w
                            selectedMonth  = nil
                        }
                    }
                }
                Spacer()
            }

            if !hasData {
                emptyPlaceholder("Pas encore de transactions pour afficher les tendances.")
            } else {
                Chart(data.bars) { bar in
                    BarMark(
                        x: .value("Mois", bar.monthLabel),
                        y: .value("Montant", bar.amount)
                    )
                    .foregroundStyle(
                        (selectedMonth != nil && selectedMonth!.label != bar.monthLabel)
                            ? (bar.kind == "Revenus" ? Color.green.opacity(0.3) : Color.red.opacity(0.3))
                            : (bar.kind == "Revenus" ? Color.green : Color.red)
                    )
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
                    AxisMarks { _ in AxisValueLabel().font(.system(size: 9)) }
                }
                .chartLegend(.hidden)
                .frame(height: 160)
                .contentShape(Rectangle())
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { val in
                                        guard let plotFrame = proxy.plotFrame else { return }
                                        let origin = geo[plotFrame].origin
                                        let x = val.location.x - origin.x
                                        if let label: String = proxy.value(atX: x) {
                                            selectedMonth = data.summaries.first { $0.label == label }
                                        }
                                    }
                                    .onEnded { _ in
                                        withAnimation(.easeOut(duration: 0.4)) {
                                            selectedMonth = nil
                                        }
                                    }
                            )
                    }
                }

                HStack(spacing: 16) {
                    legendDot(.green, "Revenus")
                    legendDot(.red,   "Dépenses")
                    Spacer()
                    Text(lang["analytics.tapBar"])
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
}

// MARK: - 3. Category Breakdown Card ──────────────────────────────────────────

struct CategoryBreakdownCard: View {
    let transactions: [Transaction]
    let currency: String

    struct Slice: Identifiable {
        var id: String { name }
        let name: String
        let colorHex: String
        let amount: Decimal
        let percent: Double
    }

    @State private var selectedSlice: Slice? = nil

    private var slices: [Slice] {
        let cal = Calendar.current
        guard let interval = cal.dateInterval(of: .month, for: .now) else { return [] }
        let monthExpenses = transactions.filter {
            $0.type == .expense && $0.account?.currency == currency &&
            $0.date >= interval.start && $0.date < interval.end
        }
        let total = monthExpenses.reduce(Decimal(0)) { $0 + $1.amount }
        guard total > 0 else { return [] }

        var dict: [String: (colorHex: String, amount: Decimal)] = [:]
        var uncategorized: Decimal = 0
        for tx in monthExpenses {
            if let cat = tx.category {
                if dict[cat.name] == nil { dict[cat.name] = (cat.colorHex, 0) }
                dict[cat.name]!.amount += tx.amount
            } else { uncategorized += tx.amount }
        }
        let grouped = dict.map { ($0.key, $0.value.colorHex, $0.value.amount) }
            .sorted { $0.2 > $1.2 }

        var result: [Slice] = []
        var others: Decimal = uncategorized
        for (i, item) in grouped.enumerated() {
            let pct = ((item.2 / total * 100) as NSDecimalNumber).doubleValue
            if i < 5 { result.append(Slice(name: item.0, colorHex: item.1, amount: item.2, percent: pct)) }
            else      { others += item.2 }
        }
        if others > 0 {
            let pct = ((others / total * 100) as NSDecimalNumber).doubleValue
            result.append(Slice(name: "Autres", colorHex: "#8E8E93", amount: others, percent: pct))
        }
        return result
    }

    private func slice(containing angleValue: Double) -> Slice? {
        var runningTotal = 0.0
        for slice in slices {
            runningTotal += slice.amount.chartDouble
            if angleValue <= runningTotal {
                return slice
            }
        }
        return slices.last
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(lang["analytics.categoryBreakdown"])
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("Ce mois · \(currency)")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            if slices.isEmpty {
                emptyPlaceholder("Aucune dépense catégorisée ce mois-ci.")
            } else {
                HStack(alignment: .center, spacing: 20) {
                    Chart(slices) { slice in
                        SectorMark(
                            angle: .value("Montant", slice.amount.chartDouble),
                            innerRadius: .ratio(0.56),
                            outerRadius: selectedSlice?.id == slice.id ? .inset(0) : .inset(6)
                        )
                        .foregroundStyle(Color(hex: slice.colorHex))
                        .opacity(selectedSlice == nil || selectedSlice?.id == slice.id ? 1 : 0.4)
                        .cornerRadius(3)
                    }
                    .chartOverlay { proxy in
                        GeometryReader { geo in
                            Rectangle().fill(.clear).contentShape(Rectangle())
                                .onTapGesture { location in
                                    guard let plotFrame = proxy.plotFrame else { return }
                                    let origin = geo[plotFrame].origin
                                    let plotLocation = CGPoint(
                                        x: location.x - origin.x,
                                        y: location.y - origin.y
                                    )
                                    let angle = proxy.angle(at: plotLocation)

                                    if let amount: Double = proxy.value(atAngle: angle),
                                       let slice = slice(containing: amount) {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            selectedSlice = selectedSlice?.id == slice.id ? nil : slice
                                        }
                                    } else {
                                        withAnimation { selectedSlice = nil }
                                    }
                                }
                        }
                    }
                    .frame(width: 110, height: 110)
                    .overlay {
                        if let sel = selectedSlice {
                            VStack(spacing: 1) {
                                Text(String(format: "%.0f%%", sel.percent))
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(Color(hex: sel.colorHex))
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(slices) { slice in
                            HStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color(hex: slice.colorHex))
                                    .frame(width: 8, height: 8)
                                Text(slice.name)
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .opacity(selectedSlice == nil || selectedSlice?.id == slice.id ? 1 : 0.4)
                                Spacer(minLength: 4)
                                if selectedSlice?.id == slice.id {
                                    Text(slice.amount.formatted(asCurrency: currency))
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(Color(hex: slice.colorHex))
                                        .transition(.opacity)
                                } else {
                                    Text(String(format: "%.0f%%", slice.percent))
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .frame(minWidth: 28, alignment: .trailing)
                                }
                            }
                            .animation(.easeInOut(duration: 0.15), value: selectedSlice?.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedSlice = selectedSlice?.id == slice.id ? nil : slice
                                }
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
        .font(.caption).foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity).padding(.vertical, 24)
}

private func legendDot(_ color: Color, _ label: String) -> some View {
    HStack(spacing: 4) {
        Circle().fill(color).frame(width: 8, height: 8)
        Text(label).font(.caption2).foregroundStyle(.secondary)
    }
}

func compactCurrency(_ v: Double, currency: String) -> String {
    let symbol = Currencies.info(for: currency).symbol
    let absV = abs(v)
    if absV >= 1_000_000 { return String(format: "%.1fM %@", v / 1_000_000, symbol) }
    if absV >= 1_000     { return String(format: "%.0fk %@", v / 1_000, symbol) }
    return String(format: "%.0f %@", v, symbol)
}

private func compactNumber(_ v: Double) -> String {
    let absV = abs(v)
    if absV >= 1_000_000 { return String(format: "%.1fM", v / 1_000_000) }
    if absV >= 1_000     { return String(format: "%.0fk", v / 1_000) }
    return String(format: "%.0f", v)
}
