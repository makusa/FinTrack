//
//  BudgetDashboardSection.swift
//  FinTrack
//
//  Two compact dashboard cards:
//   1. CashFlowCard  — projected monthly surplus/deficit
//   2. SavingsGoalsCard — progress on active savings projects
//

import SwiftUI
import SwiftData
import Charts

// MARK: - Container

struct BudgetDashboardSection: View {
    let recurring: [RecurringTransaction]
    let loans: [Loan]
    let currency: String

    @Query(filter: #Predicate<CreditLine> { $0.isActive },
           sort: \CreditLine.createdAt, order: .forward)
    private var activeCreditLines: [CreditLine]

    @Query(filter: #Predicate<SavingsProject> { $0.isActive },
           sort: \SavingsProject.createdAt, order: .forward)
    private var projects: [SavingsProject]

    private var summary: CashFlowSummary {
        CashFlowCalculator.summary(
            currency: currency,
            recurring: recurring,
            loans: loans,
            projects: projects,
            creditLines: activeCreditLines
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(lang["analytics.budget"])
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            CashFlowCard(summary: summary)
            if !projects.isEmpty {
                SavingsGoalsCard(projects: projects, currency: currency)
            }
        }
    }
}

// MARK: - 1. Cash Flow Card

struct CashFlowCard: View {
    let summary: CashFlowSummary

    var body: some View {
        NavigationLink(destination: CashFlowView(summary: summary)) {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Label("Flux mensuel estimé", systemImage: "arrow.left.arrow.right.circle.fill")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.bottom, 12)

                // Breakdown rows
                flowRow("+", label: "Revenus", amount: summary.monthlyIncome,
                        currency: summary.currency, color: .green)
                flowRow("−", label: "Dépenses", amount: summary.monthlyExpenses,
                        currency: summary.currency, color: .primary)
                if summary.monthlyLoanPayments > 0 {
                    flowRow("−", label: "Remboursements prêts", amount: summary.monthlyLoanPayments,
                            currency: summary.currency, color: .primary)
                }

                Divider().padding(.vertical, 8)

                // Net surplus
                HStack {
                    Text(lang["cashflow.surplus"])
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: summary.isPositive ? "arrow.up.right" : "arrow.down.right")
                        Text(summary.monthlySurplus.formatted(asCurrency: summary.currency))
                            .font(.subheadline.weight(.bold))
                    }
                    .foregroundStyle(summary.isPositive ? .green : .red)
                }

                // Allocation sub-rows (if projects exist)
                if summary.monthlyAllocated > 0 {
                    Divider().padding(.vertical, 8)

                    ForEach(summary.projectLines) { line in
                        HStack {
                            Text("· \(line.label)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer()
                            Text("−\(line.amount.formatted(asCurrency: summary.currency))")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 1)
                    }

                    HStack {
                        Text("Libre (non alloué)")
                            .font(.caption.weight(.semibold))
                        Spacer()
                        Text(summary.monthlyFree.formatted(asCurrency: summary.currency))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(summary.isCovered ? .green : .red)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(16)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
        }
        .buttonStyle(.plain)
    }

    private func flowRow(_ sign: String, label: String, amount: Decimal,
                         currency: String, color: Color) -> some View {
        HStack {
            Text(sign)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 12, alignment: .leading)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(amount.formatted(asCurrency: currency))
                .font(.caption.weight(.medium))
                .foregroundStyle(color)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 2. Savings Goals Card

struct SavingsGoalsCard: View {
    let projects: [SavingsProject]
    let currency: String

    private var filtered: [SavingsProject] {
        Array(projects.filter { $0.currency == currency }.prefix(3))
    }

    var body: some View {
        NavigationLink(destination: SavingsProjectsView()) {
            VStack(spacing: 0) {
                HStack {
                    Label("Projets d'épargne", systemImage: "target")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.bottom, 12)

                ForEach(Array(filtered.enumerated()), id: \.element.id) { idx, project in
                    projectMiniRow(project)
                    if idx < filtered.count - 1 {
                        Divider().padding(.vertical, 6)
                    }
                }

                if projects.count > 3 {
                    Text("+ \(projects.count - 3) autres projets")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)
                }
            }
            .padding(16)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
        }
        .buttonStyle(.plain)
    }

    private func projectMiniRow(_ p: SavingsProject) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color(hex: p.colorHex).opacity(0.15))
                        .frame(width: 28, height: 28)
                    Image(systemName: p.iconSystemName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(hex: p.colorHex))
                }
                Text(p.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Spacer()
                if let target = p.targetAmount {
                    Text("\(p.currentAmount.formatted(asCurrency: p.currency)) / \(target.formatted(asCurrency: p.currency))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text(p.currentAmount.formatted(asCurrency: p.currency))
                        .font(.caption2.weight(.medium))
                }
            }

            ProgressView(value: p.progressFraction)
                .tint(Color(hex: p.colorHex))

            HStack {
                Text(p.projectionLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if (p.monthlyContribution as NSDecimalNumber).doubleValue > 0 {
                    Text("\(p.monthlyContribution.formatted(asCurrency: p.currency))/mois")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
