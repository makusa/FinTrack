//
//  LoanDetailView.swift
//  FinTrack
//

import SwiftUI
import Charts

struct LoanDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(LanguageManager.self) private var lang
    @Bindable var loan: Loan

    @State private var showEdit = false
    @State private var showFullSchedule = false
    @State private var showAddPrepayment = false
    @State private var prepaymentToEdit: LoanPrepayment? = nil

    // Base calculator (no prepayments) — used for baseline comparisons
    private var calc: LoanCalculator { loan.calculator }

    // All prepayment instances (recurring expanded to concrete dates)
    private var preps: [PrepaymentInfo] { loan.prepaymentInstances() }

    // Prepayment-aware values
    private var currentBalance: Double { calc.currentBalanceWith(preps) }
    private var paymentsElapsed: Int   { calc.paymentsElapsedWith(preps) }
    private var paymentsRemaining: Int { calc.paymentsRemainingWith(preps) }
    private var payoffDate: Date       { calc.payoffDateWith(preps) }
    private var progressFraction: Double { calc.progressFractionWith(preps) }

    var body: some View {
        List {
            headerSection
            if loan.hasPrepayments { impactSection }
            prepaymentSection
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
            FullAmortizationView(loan: loan, prepayments: preps)
        }
        .sheet(isPresented: $showAddPrepayment) {
            AddEditPrepaymentView(mode: .create(loan: loan))
        }
        .sheet(item: $prepaymentToEdit) { prep in
            AddEditPrepaymentView(mode: .edit(prep))
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: loan.type.iconSystemName)
                    .font(.system(size: 32))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(Color.accentColor, in: Circle())

                VStack(spacing: 4) {
                    Text(Decimal(currentBalance).formatted(asCurrency: loan.currency))
                        .font(.largeTitle.weight(.bold))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text(lang["label.balance"])
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    if !loan.lenderName.isEmpty {
                        BankLogoView(domain: BankDirectory.domain(for: loan.lenderName), size: 22, cornerRadius: 5)
                    }
                    Text("\(loan.lenderName.isEmpty ? loan.type.label : loan.lenderName) · \(loan.type.label)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 4) {
                    ProgressView(value: progressFraction)
                        .tint(.green)
                    HStack {
                        Text(String(format: lang["loan.detail.paidPct"], progressFraction * 100))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(lang["loan.endDateLabel"] + ": \(payoffDate.formatted(date: .abbreviated, time: .omitted))")
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

    // MARK: - Impact card (shown only when prepayments exist)

    private var impactSection: some View {
        let savings = calc.savingsVsBaseline(preps)
        return Section(lang["prepayment.impact"]) {
            HStack(spacing: 0) {
                impactTile(
                    icon: "calendar.badge.minus",
                    color: .green,
                    value: lang.f("prepayment.savings.payments", savings.paymentsSaved),
                    label: lang["loan.paymentsRemaining"]
                )
                Divider()
                impactTile(
                    icon: "dollarsign.arrow.trianglehead.counterclockwise.rotate.90",
                    color: .orange,
                    value: Decimal(savings.interestSaved).formatted(asCurrency: loan.currency),
                    label: lang["prepayment.savings.interest"]
                )
                Divider()
                impactTile(
                    icon: "flag.checkered",
                    color: .blue,
                    value: savings.newPayoffDate.formatted(.dateTime.month(.abbreviated).year()),
                    label: lang["prepayment.newPayoffDate"]
                )
            }
            .padding(.vertical, 4)

            // Baseline vs new comparison row
            if savings.paymentsSaved > 0 {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lang["prepayment.original"])
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(calc.payoffDate.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption.weight(.medium))
                            .strikethrough(true, color: .secondary)
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lang["prepayment.newPayoffDate"])
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(savings.newPayoffDate.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                    }
                    Spacer()
                }
                .padding(.top, 2)
            }
        }
    }

    private func impactTile(icon: String, color: Color, value: String, label: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(value)
                .font(.callout.weight(.semibold))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Prepayment list section

    private var prepaymentSection: some View {
        Section {
            if loan.prepayments.isEmpty {
                Button {
                    showAddPrepayment = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(lang["prepayment.add"])
                                .foregroundStyle(.primary)
                            Text(lang["prepayment.empty.sub"])
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            } else {
                ForEach(loan.prepayments.sorted { $0.startDate < $1.startDate }) { prep in
                    PrepaymentRow(prep: prep, currency: loan.currency)
                        .contentShape(Rectangle())
                        .onTapGesture { prepaymentToEdit = prep }
                }
                Button {
                    showAddPrepayment = true
                } label: {
                    Label(lang["prepayment.add"], systemImage: "plus")
                }
            }
        } header: {
            Text(lang["prepayment.title"])
        }
    }

    // MARK: - Status section

    private var statusSection: some View {
        Section(lang["loan.situation"]) {
            loanRow(lang["loan.originalPrincipal"],
                    value: Decimal(calc.principal).formatted(asCurrency: loan.currency))
            loanRow(lang["loan.principalPaid"],
                    value: Decimal(calc.principal - currentBalance).formatted(asCurrency: loan.currency),
                    color: .green)
            loanRow(lang["loan.interestPaid"],
                    value: Decimal(calc.interestPaidToDate).formatted(asCurrency: loan.currency),
                    color: .orange)
            loanRow(lang["loan.paymentsMade"],
                    value: "\(paymentsElapsed) / \(calc.effectivePayments)")
            loanRow(lang["loan.paymentsRemaining"],
                    value: "\(paymentsRemaining)",
                    emphasis: true)
        }
    }

    // MARK: - Next payment section

    private var nextPaymentSection: some View {
        Section(lang["loan.nextPayment"]) {
            let nextEntry = calc.scheduleWithPrepayments(preps, from: paymentsElapsed + 1, to: paymentsElapsed + 1).first

            if let entry = nextEntry {
                loanRow(lang["label.date"],
                        value: entry.date.formatted(date: .long, time: .omitted))
                loanRow(lang["label.amount"],
                        value: Decimal(entry.payment).formatted(asCurrency: loan.currency),
                        emphasis: true)
                loanRow(lang["loan.detail.ofInterest"],
                        value: Decimal(entry.interest).formatted(asCurrency: loan.currency),
                        color: .orange)
                loanRow("dont capital",
                        value: Decimal(entry.principal).formatted(asCurrency: loan.currency),
                        color: .green)
            } else {
                Text(lang["loan.paidOff"])
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Total cost section

    private var progressSection: some View {
        let totalInt = calc.totalInterestWith(preps)
        let totalPaid = calc.totalAmountPaidWith(preps)
        let totalPrep = preps.reduce(0.0) { $0 + $1.amount }
        let grandTotal = totalPaid + totalPrep
        let interestRatio = grandTotal > 0 ? totalInt / grandTotal : 0

        return Section(lang["loan.totalCost"]) {
            loanRow(lang["loan.principal"],
                    value: Decimal(calc.principal).formatted(asCurrency: loan.currency))
            if totalPrep > 0 {
                loanRow(lang["prepayment.title"],
                        value: Decimal(totalPrep).formatted(asCurrency: loan.currency),
                        color: .green)
            }
            loanRow(lang["loan.totalInterest"],
                    value: Decimal(totalInt).formatted(asCurrency: loan.currency),
                    color: .orange)
            loanRow(lang["loan.totalPaid"],
                    value: Decimal(grandTotal).formatted(asCurrency: loan.currency),
                    emphasis: true)

            VStack(alignment: .leading, spacing: 4) {
                Text(lang["loan.progressSplit"])
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
                    legendDot(.orange, String(format: lang["loan.detail.interestPct"], interestRatio * 100))
                }
            }
        }
    }

    // MARK: - Upcoming schedule section

    private var upcomingScheduleSection: some View {
        let upcoming = calc.scheduleWithPrepayments(
            preps, from: paymentsElapsed + 1, to: paymentsElapsed + 12
        )

        return Section {
            if upcoming.isEmpty {
                Text(lang["loan.paidOff"]).foregroundStyle(.secondary)
            } else {
                ForEach(upcoming) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(lang.f("loan.paymentNum", entry.paymentNumber))
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
                    Text(lang.f("loan.fullSchedule", paymentsRemaining))
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        } header: {
            Text(lang["loan.upcoming12"])
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
        v >= 1000 ? String(format: "%.0fk", v / 1000) : String(format: "%.0f", v)
    }
}

// MARK: - PrepaymentRow component

private struct PrepaymentRow: View {
    @Environment(LanguageManager.self) private var lang
    let prep: LoanPrepayment
    let currency: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(prep.isRecurring ? Color.green.opacity(0.15) : Color.blue.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: prep.isRecurring ? "arrow.clockwise.circle.fill" : "arrow.up.circle.fill")
                    .foregroundStyle(prep.isRecurring ? .green : .blue)
                    .font(.system(size: 16))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(prep.amount.formatted(asCurrency: currency))
                    .font(.body.weight(.medium))
                HStack(spacing: 4) {
                    Text(prep.isRecurring ? lang["prepayment.recurring"] : lang["prepayment.oneTime"])
                        .foregroundStyle(prep.isRecurring ? .green : .blue)
                    if let freq = prep.frequency {
                        Text("· \(freq.shortLabel)")
                    }
                    if !prep.isRecurring {
                        Text("· \(prep.startDate.formatted(date: .abbreviated, time: .omitted))")
                    } else {
                        Text(lang["loan.detail.from"] + " " + prep.startDate.formatted(date: .abbreviated, time: .omitted))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let n = prep.note, !n.isEmpty {
                    Text(n)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Full amortization schedule sheet (prepayment-aware)

struct FullAmortizationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LanguageManager.self) private var lang
    let loan: Loan
    let prepayments: [PrepaymentInfo]

    private var entries: [AmortizationEntry] {
        let calc = loan.calculator
        let elapsed = calc.paymentsElapsedWith(prepayments)
        return calc.scheduleWithPrepayments(prepayments, from: elapsed + 1)
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
            .navigationTitle(lang["loan.amortization"])
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(lang["action.close"]) { dismiss() }
                }
            }
        }
    }
}
