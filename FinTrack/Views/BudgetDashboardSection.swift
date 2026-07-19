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
    @Environment(LanguageManager.self) private var lang
    @Environment(ExchangeRateManager.self) private var rates

    let monthTransactions: [Transaction]
    let recurring: [RecurringTransaction]
    let accounts: [Account]
    let displayCurrency: String

    /// Trésorerie : comptes liquides uniquement (chèque, épargne, espèces).
    private var treasuryAccounts: [Account] {
        accounts.filter { $0.type.isTreasury }
    }

    private var summary: CashFlowSummary {
        let now = Date()
        let interval = Calendar.current.dateInterval(of: .month, for: now)
        let monthStart = interval?.start ?? now
        let monthEnd   = interval?.end ?? now
        return CashFlowCalculator.summary(
            displayCurrency: displayCurrency,
            monthTransactions: monthTransactions,
            recurring: recurring,
            treasuryAccounts: treasuryAccounts,
            monthStart: monthStart,
            monthEnd: monthEnd,
            convert: { rates.convert($0, from: $1, to: $2) }
        )
    }

    var body: some View {
        CashFlowCard(summary: summary)
    }
}

// MARK: - 1. Cash Flow Card

struct CashFlowCard: View {
    @Environment(LanguageManager.self) private var lang

    let summary: CashFlowSummary

    private var approx: String { summary.hasConversion ? "≈ " : "" }

    var body: some View {
        NavigationLink(destination: CashFlowView(summary: summary)) {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Label(lang["cashflow.projection"], systemImage: "arrow.left.arrow.right.circle.fill")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.bottom, 12)

                // Build-up toward the end-of-month position
                flowRow(nil, label: lang["cashflow.currentBalance"],
                        amount: summary.currentTreasury, color: .primary)
                flowRow("+", label: lang["cashflow.upcomingIn"],
                        amount: summary.upcomingIncome, color: .green)
                flowRow("−", label: lang["cashflow.upcomingOut"],
                        amount: summary.upcomingExpense, color: .primary)

                Divider().padding(.vertical, 8)

                // Projected end-of-month position (the headline figure)
                HStack {
                    Text(lang["cashflow.projectedBalance"])
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(approx + summary.projectedEndBalance.formatted(asCurrency: summary.displayCurrency))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(summary.projectedEndBalance >= 0 ? Color.primary : Color.red)
                }

                // Realized so far this month (context)
                HStack(spacing: 8) {
                    Text(lang["cashflow.realized"])
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("+\(summary.realizedIncome.formatted(asCurrency: summary.displayCurrency))")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green)
                    Text("−\(summary.realizedExpense.formatted(asCurrency: summary.displayCurrency))")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
            }
            .padding(16)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
        }
        .buttonStyle(.plain)
    }

    private func flowRow(_ sign: String?, label: String, amount: Decimal, color: Color) -> some View {
        HStack {
            Text(sign ?? " ")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 12, alignment: .leading)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(amount.formatted(asCurrency: summary.displayCurrency))
                .font(.caption.weight(.medium))
                .foregroundStyle(color)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 2. Savings Goals Card

struct SavingsGoalsCard: View {
    let projects: [SavingsProject]   // tous les projets actifs, déjà triés (ordre manuel)

    private var visible: [SavingsProject] { Array(projects.prefix(3)) }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(visible.enumerated()), id: \.element.id) { idx, project in
                NavigationLink {
                    SavingsProjectDetailView(project: project)
                } label: {
                    projectMiniRow(project)
                }
                .buttonStyle(.plain)
                if idx < visible.count - 1 {
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
                if (p.monthlyEquivalentContribution as NSDecimalNumber).doubleValue > 0 {
                    Text("\(p.monthlyEquivalentContribution.formatted(asCurrency: p.currency))/mois")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - BudgetCard (dashboard)

struct BudgetCard: View {
    @Environment(LanguageManager.self) private var lang

    let statuses: [BudgetStatus]   // pre-filtered, max 3

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(statuses.enumerated()), id: \.element.id) { idx, status in
                budgetRow(status)
                if idx < statuses.count - 1 {
                    Divider().padding(.leading, 48)
                }
            }
        }
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    private func budgetRow(_ status: BudgetStatus) -> some View {
        let budget = status.budget
        return HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color(hex: budget.colorHex).opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: budget.iconSystemName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: budget.colorHex))
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(budget.name)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Spacer()
                    Text("\(status.spent.formatted(asCurrency: budget.currency)) / \(budget.limitAmount.formatted(asCurrency: budget.currency))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(status.progressColor)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(.systemGray5)).frame(height: 5)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(status.progressColor)
                            .frame(width: min(geo.size.width * CGFloat(min(status.fraction, 1.0)), geo.size.width), height: 5)
                    }
                }
                .frame(height: 5)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

