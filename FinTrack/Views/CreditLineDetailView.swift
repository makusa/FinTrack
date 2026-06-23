//
//  CreditLineDetailView.swift
//  FinTrack
//

import SwiftUI
import Charts

struct CreditLineDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(LanguageManager.self) private var lang
    @Bindable var creditLine: CreditLine

    @State private var showEdit         = false
    @State private var showAddEntry     = false
    @State private var defaultEntryType = CreditLineEntryType.repayment

    private var sortedEntries: [CreditLineEntry] {
        (creditLine.entries ?? []).sorted { $0.date > $1.date }
    }

    var body: some View {
        List {
            headerSection
            metricsSection
            balanceChartSection
            actionsSection
            historySection
        }
        .navigationTitle(creditLine.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { defaultEntryType = .repayment; showAddEntry = true } label: {
                        Label("Remboursement", systemImage: "arrow.up.circle.fill")
                    }
                    Button { defaultEntryType = .draw; showAddEntry = true } label: {
                        Label("Retrait", systemImage: "arrow.down.circle.fill")
                    }
                    Divider()
                    Button { showEdit = true } label: {
                        Label(lang["cl.edit"], systemImage: "pencil")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showEdit) {
            AddEditCreditLineView(mode: .edit(creditLine))
        }
        .sheet(isPresented: $showAddEntry) {
            AddCreditLineEntryView(creditLine: creditLine, defaultType: defaultEntryType)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        Section {
            VStack(spacing: 14) {
                // Utilisation gauge
                ZStack {
                    Circle()
                        .stroke(Color(.tertiarySystemBackground), lineWidth: 14)
                        .frame(width: 120, height: 120)
                    Circle()
                        .trim(from: 0, to: CGFloat(creditLine.utilisationFraction))
                        .stroke(utilisationColor, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                        .frame(width: 120, height: 120)
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 2) {
                        Text(String(format: "%.0f%%", creditLine.utilisationFraction * 100))
                            .font(.title2.weight(.bold))
                        Text(lang["cl.used"])
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .animation(.easeOut(duration: 0.6), value: creditLine.utilisationFraction)

                // Balance vs limit
                HStack(spacing: 32) {
                    statColumn(
                        label: lang["cl.balanceUsed"],
                        value: creditLine.currentBalance.formatted(asCurrency: creditLine.currency),
                        color: .red
                    )
                    Divider().frame(height: 36)
                    statColumn(
                        label: lang["cl.available"],
                        value: creditLine.availableCredit.formatted(asCurrency: creditLine.currency),
                        color: .green
                    )
                    Divider().frame(height: 36)
                    statColumn(
                        label: lang["cl.limit.short"],
                        value: creditLine.creditLimit.formatted(asCurrency: creditLine.currency),
                        color: .secondary
                    )
                }

                Text("\(creditLine.lenderName.isEmpty ? "" : creditLine.lenderName + " · ")\(String(format: "%.2f", (creditLine.annualInterestRate as NSDecimalNumber).doubleValue))% \(lang["cl.perYear"])")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .listRowBackground(Color.clear)
    }

    // MARK: - Metrics

    private var metricsSection: some View {
        Section(lang["cl.metrics"]) {
            HStack {
                Text(lang["cl.monthlyInterest"])
                    .foregroundStyle(.secondary)
                Spacer()
                Text("≈ \(creditLine.monthlyInterestEstimate.formatted(asCurrency: creditLine.currency))")
                    .foregroundStyle(.orange)
                    .fontWeight(.medium)
            }
            HStack {
                Text(lang["cl.minPayment"])
                    .foregroundStyle(.secondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(creditLine.estimatedMinimumPayment.formatted(asCurrency: creditLine.currency))
                        .fontWeight(.semibold)
                    Text(creditLine.minimumPaymentType.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                Text(lang["cl.dailyRate"])
                    .foregroundStyle(.secondary)
                Spacer()
                let daily = (creditLine.annualInterestRate as NSDecimalNumber).doubleValue / 365
                Text(String(format: "≈ %.4f%%", daily))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Balance chart

    private var balanceChartSection: some View {
        Section(lang["cl.evolution"]) {
            if sortedEntries.isEmpty {
                Text(lang["cl.noMovements"])
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
            } else {
                let points = balancePoints()
                Chart {
                    ForEach(points, id: \.0) { (date, balance) in
                        LineMark(
                            x: .value(lang["label.date"], date),
                            y: .value(lang["label.balance"], balance)
                        )
                        .foregroundStyle(Color.red)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                        .interpolationMethod(.stepEnd)

                        AreaMark(
                            x: .value(lang["label.date"], date),
                            y: .value(lang["label.balance"], balance)
                        )
                        .foregroundStyle(Color.red.opacity(0.08))
                        .interpolationMethod(.stepEnd)
                    }

                    // Credit limit reference line
                    let limitDouble = (creditLine.creditLimit as NSDecimalNumber).doubleValue
                    RuleMark(y: .value(lang["cl.limit.short"], limitDouble))
                        .foregroundStyle(Color.orange.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                        .annotation(position: .top, alignment: .trailing) {
                            Text(lang["cl.limit.short"])
                                .font(.system(size: 9))
                                .foregroundStyle(.orange)
                                .padding(.trailing, 4)
                        }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine().foregroundStyle(Color(.separator).opacity(0.4))
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(compactAmount(v, currency: creditLine.currency))
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
                                .locale(LanguageManager.shared.locale)
                        ).font(.system(size: 9))
                    }
                }
                .frame(height: 160)
            }
        }
    }

    // MARK: - Quick actions

    private var actionsSection: some View {
        Section {
            Button {
                defaultEntryType = .repayment
                showAddEntry = true
            } label: {
                Label("Enregistrer un remboursement", systemImage: "arrow.up.circle.fill")
                    .foregroundStyle(.green)
            }
            Button {
                defaultEntryType = .draw
                showAddEntry = true
            } label: {
                Label("Enregistrer un retrait", systemImage: "arrow.down.circle.fill")
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - History

    private var historySection: some View {
        Section(lang.f("cl.history", sortedEntries.count)) {
            if sortedEntries.isEmpty {
                Text(lang["cl.noHistory"])
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(sortedEntries) { entry in
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color(hex: entry.type.color).opacity(0.15))
                                .frame(width: 36, height: 36)
                            Image(systemName: entry.type.iconSystemName)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color(hex: entry.type.color))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.type.label)
                                .font(.callout.weight(.medium))
                            if !entry.note.isEmpty {
                                Text(entry.note)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            let sign = entry.type == .repayment ? "−" : "+"
                            let color: Color = entry.type == .repayment ? .green
                                : entry.type == .draw ? .red : .orange
                            Text("\(sign)\(entry.amount.formatted(asCurrency: creditLine.currency))")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(color)
                            Text(entry.date.appFormatted())
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .onDelete(perform: deleteEntries)
            }
        }
    }

    // MARK: - Helpers

    private var utilisationColor: Color {
        let u = creditLine.utilisationFraction
        if u >= 0.9 { return .red }
        if u >= 0.7 { return .orange }
        return .green
    }

    private func statColumn(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.callout.weight(.bold))
                .foregroundStyle(color)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func balancePoints() -> [(Date, Double)] {
        let sorted = (creditLine.entries ?? []).sorted { $0.date < $1.date }
        var running: Double = 0
        var points: [(Date, Double)] = []
        for entry in sorted {
            running = max(0, running + (entry.signedAmount as NSDecimalNumber).doubleValue)
            points.append((entry.date, running))
        }
        // Extend to today
        if let last = points.last, last.0 < Date() {
            points.append((Date(), last.1))
        }
        return points
    }

    private func deleteEntries(at offsets: IndexSet) {
        let toDelete = offsets.map { sortedEntries[$0] }
        for entry in toDelete {
            // Don't delete auto-generated interest entries manually
            guard entry.type != .interestAccrual else { continue }
            context.delete(entry)
        }
        try? context.save()
    }
}

private func compactAmount(_ v: Double, currency: String) -> String {
    let sym = Currencies.info(for: currency).symbol
    if abs(v) >= 1_000_000 { return String(format: "%.1fM %@", v / 1_000_000, sym) }
    if abs(v) >= 1_000     { return String(format: "%.0fk %@", v / 1_000, sym) }
    return String(format: "%.0f %@", v, sym)
}
