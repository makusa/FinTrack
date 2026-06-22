//
//  SavingsProjectsView.swift
//  FinTrack
//

import SwiftUI
import SwiftData
import Charts

// MARK: - List

struct SavingsProjectsView: View {
    @Environment(\.modelContext) private var context
    @Environment(LanguageManager.self) private var lang
    @Environment(EntitlementManager.self) private var entitlements

    @Query(filter: #Predicate<SavingsProject> { $0.isActive },
           sort: \SavingsProject.createdAt, order: .forward)
    private var activeProjects: [SavingsProject]

    @Query(filter: #Predicate<SavingsProject> { !$0.isActive },
           sort: \SavingsProject.createdAt, order: .forward)
    private var archivedProjects: [SavingsProject]

    @State private var showAdd = false
    @State private var showArchived = false

    private var isAtFreeLimit: Bool {
        !entitlements.hasPaidTier && activeProjects.count >= FinTrackLimit.freeMaxSavingsProjects
    }

    // Total by currency
    private var totalsByCurrency: [(currency: String, total: Decimal)] {
        let all = activeProjects
        let grouped = Dictionary(grouping: all, by: \.currency)
        return grouped
            .map { (currency: $0.key, total: $0.value.reduce(Decimal(0)) { $0 + $1.currentAmount }) }
            .sorted { $0.currency < $1.currency }
    }

    var body: some View {
        List {
            if activeProjects.isEmpty {
                emptyState
            } else {
                // Totals strip
                Section {
                    ForEach(totalsByCurrency, id: \.currency) { row in
                        HStack {
                            Label(lang["savings.total.byCurrency"] + " (\(row.currency))", systemImage: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                            Spacer()
                            Text(row.total.formatted(asCurrency: row.currency))
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.green)
                        }
                    }
                }

                Section(lang.f("savings.myProjects", activeProjects.count)) {
                    ForEach(activeProjects) { project in
                        NavigationLink {
                            SavingsProjectDetailView(project: project)
                        } label: {
                            SavingsProjectRow(project: project)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { delete(project) } label: {
                                Label(lang["action.delete"], systemImage: "trash")
                            }
                            Button { archive(project) } label: {
                                Label(lang["action.archive"], systemImage: "archivebox")
                            }
                            .tint(.orange)
                        }
                    }
                }
            }

            if !archivedProjects.isEmpty {
                Section {
                    DisclosureGroup(isExpanded: $showArchived) {
                        ForEach(archivedProjects) { project in
                            NavigationLink {
                                SavingsProjectDetailView(project: project)
                            } label: {
                                SavingsProjectRow(project: project).opacity(0.5)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { delete(project) } label: {
                                    Label(lang["action.delete"], systemImage: "trash")
                                }
                                Button { archive(project) } label: {
                                    Label(lang["action.resume"], systemImage: "tray.and.arrow.up")
                                }
                                .tint(.green)
                            }
                        }
                    } label: {
                        Text(lang.f("savings.archived", archivedProjects.count))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(lang["savings.title"])
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: {
                    Image(systemName: "plus.circle.fill").font(.title3)
                }
                .disabled(isAtFreeLimit)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isAtFreeLimit { freeCapBanner }
        }
        .sheet(isPresented: $showAdd) {
            if isAtFreeLimit {
                NavigationStack {
                    ProGateView(feature: .savings)
                        .environment(entitlements)
                }
            } else {
                AddEditSavingsProjectView(mode: .create)
            }
        }
    }

    private var freeCapBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(lang["savings.free.cap.title"])
                    .font(.callout.weight(.semibold))
                Text(lang["savings.free.cap.subtitle"])
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            NavigationLink {
                SubscriptionView().environment(entitlements)
            } label: {
                Text(lang["entitlement.pro.cta"])
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color.orange.opacity(0.15), in: Capsule())
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "target")
                .font(.system(size: 44)).foregroundStyle(.tint).padding(.top, 32)
            Text(lang["savings.empty.title"])
                .font(.headline)
            Text(lang["savings.empty.sub"])
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 24)
            Button { showAdd = true } label: {
                Label(lang["savings.create"], systemImage: "plus")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20).padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent).padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func archive(_ p: SavingsProject) { p.isActive.toggle(); try? context.save() }
    private func delete(_ p: SavingsProject)  {
        SavingsTransferService.cleanupOnDelete(p, removeGenerated: false, context: context)
        context.delete(p)
        try? context.save()
    }
}

// MARK: - Row

struct SavingsProjectRow: View {
    let project: SavingsProject
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color(hex: project.colorHex).opacity(0.15)).frame(width: 42, height: 42)
                Image(systemName: project.iconSystemName)
                    .foregroundStyle(Color(hex: project.colorHex))
                    .font(.system(size: 18, weight: .semibold))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(project.name).font(.body.weight(.medium)).lineLimit(1)
                ProgressView(value: project.progressFraction).tint(Color(hex: project.colorHex))
                Text(project.projectionLabel).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(project.currentAmount.formatted(asCurrency: project.currency))
                    .font(.callout.weight(.semibold))
                if let target = project.targetAmount {
                    Text("/ \(target.formatted(asCurrency: project.currency))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Detail

struct SavingsProjectDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(LanguageManager.self) private var lang
    @Bindable var project: SavingsProject
    @State private var showEdit       = false
    @State private var scrubDate:    Date?   = nil
    @State private var scrubAmount:  Double? = nil
    @State private var chartRange:   SavingsChartRange = .all

    private var calc: ProjectionData {
        // Not tier-gated: the projection always runs to the goal (capped at 10 years).
        ProjectionData(project: project)
    }

    /// Ranges worth offering, given how far the projection actually extends.
    private var availableRanges: [SavingsChartRange] {
        let spanMonths = max(calc.points.count - 1, 0)
        var ranges: [SavingsChartRange] = []
        if spanMonths > 12 { ranges.append(.oneYear) }
        if spanMonths > 60 { ranges.append(.fiveYears) }
        ranges.append(.all)
        return ranges
    }

    /// Visible X window for the chart, driven by the range selector.
    private var effectiveXDomain: ClosedRange<Date> {
        let first = calc.points.first?.date ?? Date()
        let last  = calc.points.last?.date ?? Date()
        guard let months = chartRange.months else { return first...last }
        let end = Calendar.current.date(byAdding: .month, value: months, to: first) ?? last
        return first...min(end, last)
    }

    /// X-axis label stride adapted to the visible window.
    private var visibleStrideMonths: Int {
        let visible = chartRange.months.map { min($0, max(calc.points.count - 1, 1)) }
            ?? max(calc.points.count - 1, 1)
        return visible <= 12 ? 2 : (visible <= 36 ? 6 : 12)
    }

    var body: some View {
        List {
            headerSection
            statusSection
            projectionChartSection
            metricsSection
            if showEdit { Color.clear }
        }
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showEdit = true } label: { Image(systemName: "pencil") }
            }
        }
        .sheet(isPresented: $showEdit) {
            AddEditSavingsProjectView(mode: .edit(project))
        }
    }

    // MARK: Sections

    private var headerSection: some View {
        Section {
            VStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color(hex: project.colorHex).opacity(0.15)).frame(width: 72, height: 72)
                    Image(systemName: project.iconSystemName)
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(Color(hex: project.colorHex))
                }
                Text(project.currentAmount.formatted(asCurrency: project.currency))
                    .font(.largeTitle.weight(.bold))
                if let target = project.targetAmount {
                    Text(lang["savings.of"] + " " + target.formatted(asCurrency: project.currency))
                        .font(.subheadline).foregroundStyle(.secondary)
                    ProgressView(value: project.progressFraction)
                        .tint(Color(hex: project.colorHex))
                        .padding(.horizontal, 24)
                    Text(String(format: lang["savings.pct.reached"], project.progressFraction * 100))
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(lang["savings.freeAccumulation"]).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity).padding(.vertical, 8)
        }
        .listRowBackground(Color.clear)
    }

    private var statusSection: some View {
        Section(lang["savings.currentAmount.section"]) {
            row(lang["savings.detail.saved"], value: project.currentAmount.formatted(asCurrency: project.currency))
            if let target = project.targetAmount {
                row(lang["savings.target"], value: target.formatted(asCurrency: project.currency))
                row(lang["savings.detail.remaining"], value: project.amountRemaining?.formatted(asCurrency: project.currency) ?? "—",
                    color: .orange)
            }
            row(lang["savings.contribution"],
                value: (project.monthlyContribution as NSDecimalNumber).doubleValue > 0
                    ? project.monthlyContribution.formatted(asCurrency: project.currency) + project.transferFrequency.unitSuffix
                    : lang["savings.detail.noDeadline"],
                emphasis: true)
        }
    }

    private var projectionChartSection: some View {
        Section {
            if calc.points.isEmpty {
                Text(lang["savings.projectionEmpty"])
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
            } else {
                VStack(alignment: .leading, spacing: 10) {

                    // ── Range selector (only when more than one range is useful) ──
                    if availableRanges.count > 1 {
                        Picker("", selection: $chartRange) {
                            ForEach(availableRanges) { r in Text(r.label).tag(r) }
                        }
                        .pickerStyle(.segmented)
                    }

                    // ── Scrubber readout ──────────────────────────────────
                    HStack {
                        if let d = scrubDate, let a = scrubAmount {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(d.formatted(.dateTime.month(.wide).year().locale(LanguageManager.shared.locale)))
                                    .font(.caption2).foregroundStyle(.secondary)
                                Text(Decimal(a).formatted(asCurrency: project.currency))
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(Color(hex: project.colorHex))
                                if let target = project.targetAmount {
                                    let remaining = max(0, (target as NSDecimalNumber).doubleValue - a)
                                    Text(remaining <= 0
                                         ? lang["savings.goalReached.check"]
                                         : String(format: lang["savings.scrub.remaining"], Decimal(remaining).formatted(asCurrency: project.currency)))
                                        .font(.caption2)
                                        .foregroundStyle(remaining <= 0 ? AnyShapeStyle(Color.green) : AnyShapeStyle(.secondary))
                                }
                            }
                            .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .leading)))
                        } else {
                            Text(lang["savings.scrubHint"])
                                .font(.caption2).foregroundStyle(.tertiary)
                                .transition(.opacity)
                        }
                        Spacer()
                    }
                    .animation(.easeInOut(duration: 0.15), value: scrubDate != nil)
                    .frame(minHeight: 38)

                    // ── Chart ─────────────────────────────────────────────
                    Chart {
                        ForEach(calc.points) { point in
                            LineMark(
                                x: .value("Date", point.date),
                                y: .value("Montant", point.amount)
                            )
                            .foregroundStyle(Color(hex: project.colorHex))
                            .lineStyle(StrokeStyle(lineWidth: 2.5))
                            .interpolationMethod(.monotone)

                            AreaMark(
                                x: .value("Date", point.date),
                                y: .value("Montant", point.amount)
                            )
                            .foregroundStyle(Color(hex: project.colorHex).opacity(0.1))
                            .interpolationMethod(.monotone)
                        }

                        if let target = project.targetAmount {
                            let t = (target as NSDecimalNumber).doubleValue
                            RuleMark(y: .value("Objectif", t))
                                .foregroundStyle(Color(hex: project.colorHex).opacity(0.6))
                                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                                .annotation(position: .top, alignment: .trailing) {
                                    Text(lang["savings.target"])
                                        .font(.system(size: 9))
                                        .foregroundStyle(Color(hex: project.colorHex))
                                        .padding(.trailing, 4)
                                }
                        }

                        RuleMark(x: .value("Auj.", Date()))
                            .foregroundStyle(.secondary.opacity(0.4))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))

                        // Scrubber
                        if let d = scrubDate, let a = scrubAmount {
                            RuleMark(x: .value("Sélection", d))
                                .foregroundStyle(Color.primary.opacity(0.5))
                                .lineStyle(StrokeStyle(lineWidth: 1.5))
                            PointMark(x: .value("Date", d), y: .value("Montant", a))
                                .symbolSize(60)
                                .foregroundStyle(Color(hex: project.colorHex))
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine().foregroundStyle(Color(.separator).opacity(0.5))
                            AxisValueLabel {
                                if let v = value.as(Double.self) {
                                    Text(compactAmount(v, currency: project.currency))
                                        .font(.system(size: 9))
                                }
                            }
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .month, count: visibleStrideMonths)) { _ in
                            AxisGridLine().foregroundStyle(Color(.separator).opacity(0.3))
                            AxisValueLabel(
                                format: .dateTime.month(.abbreviated).locale(LanguageManager.shared.locale)
                            ).font(.system(size: 9))
                        }
                    }
                    .frame(height: 200)
                    .chartXScale(domain: effectiveXDomain)
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
                                            guard x >= 0 else { return }
                                            if let raw: Date = proxy.value(atX: x),
                                               let nearest = calc.points.min(by: {
                                                   abs($0.date.timeIntervalSince(raw)) < abs($1.date.timeIntervalSince(raw))
                                               }) {
                                                scrubDate   = nearest.date
                                                scrubAmount = nearest.amount
                                            }
                                        }
                                        .onEnded { _ in
                                            withAnimation(.easeOut(duration: 0.4)) {
                                                scrubDate   = nil
                                                scrubAmount = nil
                                            }
                                        }
                                )
                        }
                    }
                }
            }
        } header: {
            Text(lang["savings.projection"])
        }
    }

    private var metricsSection: some View {
        Section(lang["savings.indicators"]) {
            if let reachDate = project.targetReachDate {
                row(lang["savings.targetReach"],
                    value: reachDate.appFormattedLong(),
                    emphasis: true)
                if let months = project.monthsToTarget {
                    row(lang["savings.monthsLeft"], value: String(format: lang["savings.projection.months"], months))
                }
            } else if project.targetAmount != nil {
                row(lang["savings.detail.reachDate"], value: lang["savings.detail.noContrib"])
            }

            if let req = project.requiredMonthlyForDeadline {
                let perTransfer = req / Decimal(project.transferFrequency.approxPeriodsPerMonth)
                row(lang["savings.requiredContrib"],
                    value: perTransfer.formatted(asCurrency: project.currency) + project.transferFrequency.unitSuffix,
                    color: req > project.monthlyEquivalentContribution ? .orange : .green)
            }
        }
    }

    // MARK: Helpers

    private func row(_ label: String, value: String, color: Color = .primary, emphasis: Bool = false) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(emphasis ? .body.weight(.semibold) : .body)
                .foregroundStyle(color)
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - Chart range

enum SavingsChartRange: String, CaseIterable, Identifiable {
    case oneYear, fiveYears, all
    var id: String { rawValue }
    var months: Int? {
        switch self {
        case .oneYear:   return 12
        case .fiveYears: return 60
        case .all:       return nil
        }
    }
    var label: String {
        switch self {
        case .oneYear:   return LanguageManager.shared["savings.range.1y"]
        case .fiveYears: return LanguageManager.shared["savings.range.5y"]
        case .all:       return LanguageManager.shared["savings.range.all"]
        }
    }
}

// MARK: - Projection data

private struct ProjectionPoint: Identifiable {
    let id = UUID()
    let date: Date
    let amount: Double
}

private struct ProjectionData {
    let points: [ProjectionPoint]
    let xStrideMonths: Int

    init(project: SavingsProject, maxMonths: Int = 120) {
        let monthly = (project.monthlyEquivalentContribution as NSDecimalNumber).doubleValue
        guard monthly > 0 else { points = []; xStrideMonths = 3; return }

        let current = (project.currentAmount as NSDecimalNumber).doubleValue
        let cal = Calendar.current

        // How many months to show? Runs to the goal (+3 months padding), capped at maxMonths.
        let totalMonths: Int
        if let months = project.monthsToTarget {
            totalMonths = min(months + 3, maxMonths)
        } else {
            totalMonths = min(24, maxMonths)
        }

        var pts: [ProjectionPoint] = []
        let startOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: .now)) ?? .now
        for i in 0...totalMonths {
            guard let date = cal.date(byAdding: .month, value: i, to: startOfMonth) else { continue }
            var amount = current + monthly * Double(i)
            if let target = project.targetAmount {
                amount = min(amount, (target as NSDecimalNumber).doubleValue)
            }
            pts.append(ProjectionPoint(date: date, amount: amount))
        }

        points = pts
        xStrideMonths = totalMonths <= 12 ? 2 : (totalMonths <= 36 ? 6 : 12)
    }
}

private func compactAmount(_ v: Double, currency: String) -> String {
    let symbol = Currencies.info(for: currency).symbol
    if abs(v) >= 1_000_000 { return String(format: "%.1fM %@", v / 1_000_000, symbol) }
    if abs(v) >= 1_000     { return String(format: "%.0fk %@", v / 1_000, symbol) }
    return String(format: "%.0f %@", v, symbol)
}
