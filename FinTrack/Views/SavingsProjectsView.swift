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

    @Query(filter: #Predicate<SavingsProject> { $0.isActive },
           sort: \SavingsProject.createdAt, order: .forward)
    private var activeProjects: [SavingsProject]

    @Query(filter: #Predicate<SavingsProject> { !$0.isActive },
           sort: \SavingsProject.createdAt, order: .forward)
    private var archivedProjects: [SavingsProject]

    @State private var showAdd = false
    @State private var showArchived = false

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
                            Label("Épargne totale (\(row.currency))", systemImage: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                            Spacer()
                            Text(row.total.formatted(asCurrency: row.currency))
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.green)
                        }
                    }
                }

                Section("Mes projets (\(activeProjects.count))") {
                    ForEach(activeProjects) { project in
                        NavigationLink {
                            SavingsProjectDetailView(project: project)
                        } label: {
                            SavingsProjectRow(project: project)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { delete(project) } label: {
                                Label("Supprimer", systemImage: "trash")
                            }
                            Button { archive(project) } label: {
                                Label("Archiver", systemImage: "archivebox")
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
                                    Label("Supprimer", systemImage: "trash")
                                }
                                Button { archive(project) } label: {
                                    Label("Réactiver", systemImage: "tray.and.arrow.up")
                                }
                                .tint(.green)
                            }
                        }
                    } label: {
                        Text("Archivés (\(archivedProjects.count))")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Projets d'épargne")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: {
                    Image(systemName: "plus.circle.fill").font(.title3)
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddEditSavingsProjectView(mode: .create)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "target")
                .font(.system(size: 44)).foregroundStyle(.tint).padding(.top, 32)
            Text("Aucun projet d'épargne")
                .font(.headline)
            Text("Définissez un objectif — voyage, fonds d'urgence, achat — et FinTrack calculera quand vous l'atteindrez en fonction de votre surplus mensuel.")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 24)
            Button { showAdd = true } label: {
                Label("Créer un projet", systemImage: "plus")
                    .font(.body.weight(.semibold))
                    .padding(.horizontal, 20).padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent).padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func archive(_ p: SavingsProject) { p.isActive.toggle(); try? context.save() }
    private func delete(_ p: SavingsProject)  { context.delete(p); try? context.save() }
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
    @Bindable var project: SavingsProject
    @State private var showEdit = false

    private var calc: ProjectionData { ProjectionData(project: project) }

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
                    Text("sur \(target.formatted(asCurrency: project.currency))")
                        .font(.subheadline).foregroundStyle(.secondary)
                    ProgressView(value: project.progressFraction)
                        .tint(Color(hex: project.colorHex))
                        .padding(.horizontal, 24)
                    Text(String(format: "%.1f%% atteint", project.progressFraction * 100))
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Accumulation libre").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity).padding(.vertical, 8)
        }
        .listRowBackground(Color.clear)
    }

    private var statusSection: some View {
        Section("Situation actuelle") {
            row("Épargné", value: project.currentAmount.formatted(asCurrency: project.currency))
            if let target = project.targetAmount {
                row("Objectif", value: target.formatted(asCurrency: project.currency))
                row("Restant", value: project.amountRemaining?.formatted(asCurrency: project.currency) ?? "—",
                    color: .orange)
            }
            row("Contribution mensuelle",
                value: (project.monthlyContribution as NSDecimalNumber).doubleValue > 0
                    ? project.monthlyContribution.formatted(asCurrency: project.currency) + "/mois"
                    : "Non définie",
                emphasis: true)
        }
    }

    private var projectionChartSection: some View {
        Section {
            if calc.points.isEmpty {
                Text("Définissez une contribution mensuelle pour voir la projection.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
            } else {
                VStack(alignment: .leading, spacing: 8) {
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
                                    Text("Objectif")
                                        .font(.system(size: 9))
                                        .foregroundStyle(Color(hex: project.colorHex))
                                        .padding(.trailing, 4)
                                }
                        }

                        RuleMark(x: .value("Aujourd'hui", Date()))
                            .foregroundStyle(.secondary.opacity(0.4))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
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
                        AxisMarks(values: .stride(by: .month, count: calc.xStrideMonths)) { _ in
                            AxisGridLine().foregroundStyle(Color(.separator).opacity(0.3))
                            AxisValueLabel(
                                format: .dateTime.month(.abbreviated).locale(Locale(identifier: "fr_CA"))
                            ).font(.system(size: 9))
                        }
                    }
                    .frame(height: 180)
                }
            }
        } header: {
            Text("Projection")
        }
    }

    private var metricsSection: some View {
        Section("Indicateurs") {
            if let reachDate = project.targetReachDate {
                row("Date d'atteinte estimée",
                    value: reachDate.formatted(date: .long, time: .omitted),
                    emphasis: true)
                if let months = project.monthsToTarget {
                    row("Mois restants", value: "\(months) mois")
                }
            } else if project.targetAmount != nil {
                row("Date d'atteinte", value: "Définissez une contribution mensuelle")
            }

            if let req = project.requiredMonthlyForDeadline {
                row("Contribution requise (échéance)",
                    value: req.formatted(asCurrency: project.currency) + "/mois",
                    color: req > project.monthlyContribution ? .orange : .green)
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

// MARK: - Projection data

private struct ProjectionPoint: Identifiable {
    let id = UUID()
    let date: Date
    let amount: Double
}

private struct ProjectionData {
    let points: [ProjectionPoint]
    let xStrideMonths: Int

    init(project: SavingsProject) {
        let monthly = (project.monthlyContribution as NSDecimalNumber).doubleValue
        guard monthly > 0 else { points = []; xStrideMonths = 3; return }

        let current = (project.currentAmount as NSDecimalNumber).doubleValue
        let cal = Calendar.current

        // How many months to show?
        let totalMonths: Int
        if let months = project.monthsToTarget {
            totalMonths = min(months + 3, 120)  // cap at 10 years
        } else {
            totalMonths = 24
        }

        var pts: [ProjectionPoint] = []
        for i in 0...totalMonths {
            guard let date = cal.date(byAdding: .month, value: i, to: .now) else { continue }
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
