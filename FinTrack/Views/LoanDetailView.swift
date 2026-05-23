//
//  LoanDetailView.swift
//  FinTrack
//

import SwiftUI
import Charts

struct LoanDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var loan: Loan

    @State private var showEdit = false
    @State private var showFullSchedule = false

    private var calc: LoanCalculator { loan.calculator }

    var body: some View {
        List {
            headerSection
            statusSection
            nextPaymentSection
            progressSection
            upcomingScheduleSection
        }
        .navigationTitle(loan.label)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showEdit = true } label: {
                    Image(systemName: "pencil")
                }
            }
        }
        .sheet(isPresented: $showEdit) {
            AddEditLoanView(mode: .edit(loan))
        }
        .sheet(isPresented: $showFullSchedule) {
            FullAmortizationView(loan: loan)
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        Section {
            VStack(spacing: 12) {
                // Icon
                Image(systemName: loan.type.iconSystemName)
                    .font(.system(size: 32))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(Color.accentColor, in: Circle())

                // Remaining balance
                VStack(spacing: 4) {
                    Text(Decimal(calc.currentBalance).formatted(asCurrency: loan.currency))
                        .font(.largeTitle.weight(.bold))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text("Solde restant")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Lender + type
                Text("\(loan.lenderName.isEmpty ? loan.type.labelFR : loan.lenderName) · \(loan.type.labelFR)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                // Progress bar
                VStack(spacing: 4) {
                    ProgressView(value: calc.progressFraction)
                        .tint(.green)
                    HStack {
                        Text(String(format: "%.1f%% remboursé", calc.progressFraction * 100))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("Fin: \(calc.payoffDate.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .listRowBackground(Color.clear)
    }

    private var statusSection: some View {
        Section("Situation actuelle") {
            loanRow("Capital initial",
                    value: Decimal(calc.principal).formatted(asCurrency: loan.currency))
            loanRow("Capital remboursé",
                    value: Decimal(calc.principalPaid).formatted(asCurrency: loan.currency),
                    color: .green)
            loanRow("Intérêts payés à ce jour",
                    value: Decimal(calc.interestPaidToDate).formatted(asCurrency: loan.currency),
                    color: .orange)
            loanRow("Versements effectués",
                    value: "\(calc.paymentsElapsedToday) / \(calc.effectivePayments)")
            loanRow("Versements restants",
                    value: "\(calc.paymentsRemaining)",
                    emphasis: true)
        }
    }

    private var nextPaymentSection: some View {
        Section("Prochain versement") {
            let elapsed = calc.paymentsElapsedToday
            let nextEntry = calc.schedule(from: elapsed + 1, to: elapsed + 1).first

            if let entry = nextEntry {
                loanRow("Date",
                        value: entry.date.formatted(date: .long, time: .omitted))
                loanRow("Montant total",
                        value: Decimal(entry.payment).formatted(asCurrency: loan.currency),
                        emphasis: true)
                loanRow("dont intérêts",
                        value: Decimal(entry.interest).formatted(asCurrency: loan.currency),
                        color: .orange)
                loanRow("dont capital",
                        value: Decimal(entry.principal).formatted(asCurrency: loan.currency),
                        color: .green)
            } else {
                Text("Prêt entièrement remboursé.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var progressSection: some View {
        Section("Coût total") {
            loanRow("Montant emprunté",
                    value: Decimal(calc.principal).formatted(asCurrency: loan.currency))
            loanRow("Total des intérêts",
                    value: Decimal(calc.totalInterest).formatted(asCurrency: loan.currency),
                    color: .orange)
            loanRow("Coût total du prêt",
                    value: Decimal(calc.totalAmountPaid).formatted(asCurrency: loan.currency),
                    emphasis: true)

            // Mini bar showing principal vs interest split
            let interestRatio = calc.principal > 0
                ? calc.totalInterest / calc.totalAmountPaid : 0
            VStack(alignment: .leading, spacing: 4) {
                Text("Répartition capital / intérêts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.accentColor)
                            .frame(width: geo.size.width * CGFloat(1 - interestRatio))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.orange)
                            .frame(width: geo.size.width * CGFloat(interestRatio))
                    }
                    .frame(height: 8)
                }
                .frame(height: 8)
                HStack {
                    legendDot(.accentColor, String(format: "Capital %.0f%%", (1 - interestRatio) * 100))
                    legendDot(.orange, String(format: "Intérêts %.0f%%", interestRatio * 100))
                }
            }
        }
    }

    private var upcomingScheduleSection: some View {
        let elapsed = calc.paymentsElapsedToday
        let upcoming = calc.schedule(from: elapsed + 1, to: elapsed + 12)

        return Section {
            if upcoming.isEmpty {
                Text("Prêt entièrement remboursé.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(upcoming) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Versement #\(entry.paymentNumber)")
                                .font(.caption.weight(.medium))
                            Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(Decimal(entry.payment).formatted(asCurrency: loan.currency))
                                .font(.caption.weight(.semibold))
                            HStack(spacing: 6) {
                                Text("K: \(compactAmount(entry.principal))")
                                    .foregroundStyle(.green)
                                Text("I: \(compactAmount(entry.interest))")
                                    .foregroundStyle(.orange)
                            }
                            .font(.caption2)
                        }
                    }
                    .padding(.vertical, 2)
                }

                Button { showFullSchedule = true } label: {
                    Text("Voir le tableau complet (\(calc.paymentsRemaining) versements)")
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        } header: {
            Text("Prochains versements (12 mois)")
        }
    }

    // MARK: - Helpers

    private func loanRow(_ title: String, value: String,
                         color: Color = .primary, emphasis: Bool = false) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(emphasis ? .body.weight(.semibold) : .body)
                .foregroundStyle(color)
        }
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func compactAmount(_ v: Double) -> String {
        if v >= 1000 { return String(format: "%.0fk", v / 1000) }
        return String(format: "%.0f", v)
    }
}

// MARK: - Full amortization schedule sheet

struct FullAmortizationView: View {
    @Environment(\.dismiss) private var dismiss
    let loan: Loan

    private var entries: [AmortizationEntry] {
        let calc = loan.calculator
        return calc.schedule(from: calc.paymentsElapsedToday + 1)
    }

    var body: some View {
        NavigationStack {
            List(entries) { entry in
                HStack(spacing: 8) {
                    Text("#\(entry.paymentNumber)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 28, alignment: .leading)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption.weight(.medium))
                        Text(Decimal(entry.balance).formatted(asCurrency: loan.currency))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 1) {
                        Text(Decimal(entry.payment).formatted(asCurrency: loan.currency))
                            .font(.caption.weight(.semibold))
                        HStack(spacing: 4) {
                            Text("K \(Decimal(entry.principal).formatted(asCurrency: loan.currency))")
                                .foregroundStyle(.green)
                            Text("I \(Decimal(entry.interest).formatted(asCurrency: loan.currency))")
                                .foregroundStyle(.orange)
                        }
                        .font(.caption2)
                    }
                }
                .padding(.vertical, 2)
            }
            .navigationTitle("Tableau d'amortissement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }
}
