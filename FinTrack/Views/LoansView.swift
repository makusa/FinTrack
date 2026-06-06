//
//  LoansView.swift
//  FinTrack
//

import SwiftUI
import SwiftData

struct LoansView: View {
    @Environment(\.modelContext) private var context
    @Environment(LanguageManager.self) private var lang
    @State private var entitlements = EntitlementManager.shared

    @Query(filter: #Predicate<Loan> { $0.isActive },
           sort: \Loan.createdAt, order: .forward)
    private var activeLoans: [Loan]

    @Query(filter: #Predicate<Loan> { !$0.isActive },
           sort: \Loan.createdAt, order: .forward)
    private var archivedLoans: [Loan]

    @State private var showAdd = false
    @State private var showArchived = false

    // Total remaining debt grouped by currency
    private var debtByCurrency: [(currency: String, total: Decimal)] {
        let grouped = Dictionary(grouping: activeLoans, by: \.currency)
        return grouped
            .map { (currency: $0.key, total: $0.value.reduce(Decimal(0)) {
                $0 + Decimal($1.calculator.currentBalance)
            }) }
            .sorted { $0.currency < $1.currency }
    }

    var body: some View {
        List {
            if activeLoans.isEmpty {
                emptyState
            } else {
                // Debt summary strip
                debtSummarySection

                Section(lang["loan.title"]) {
                    ForEach(activeLoans) { loan in
                        NavigationLink { LoanDetailView(loan: loan) } label: {
                            LoanRow(loan: loan)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { delete(loan) } label: {
                                Label(lang["action.delete"], systemImage: "trash")
                            }
                            Button { archive(loan) } label: {
                                Label(lang["action.archive"], systemImage: "archivebox")
                            }
                            .tint(.orange)
                        }
                    }
                }
            }

            if !archivedLoans.isEmpty {
                Section {
                    DisclosureGroup(isExpanded: $showArchived) {
                        ForEach(archivedLoans) { loan in
                            NavigationLink { LoanDetailView(loan: loan) } label: {
                                LoanRow(loan: loan).opacity(0.5)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { delete(loan) } label: {
                                    Label(lang["action.delete"], systemImage: "trash")
                                }
                                Button { archive(loan) } label: {
                                    Label(lang["action.resume"], systemImage: "tray.and.arrow.up")
                                }
                                .tint(.green)
                            }
                        }
                    } label: {
                        Text(lang.f("account.archived", archivedLoans.count))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(lang["loan.title"])
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: {
                    Image(systemName: "plus.circle.fill").font(.title3)
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddEditLoanView(mode: .create)
        }
    }

    // MARK: - Sections

    private var debtSummarySection: some View {
        Section {
            ForEach(debtByCurrency, id: \.currency) { row in
                HStack {
                    Label(lang["loan.totalDebt"] + " (\(row.currency))", systemImage: "minus.circle.fill")
                        .foregroundStyle(.red)
                    Spacer()
                    Text(row.total.formatted(asCurrency: row.currency))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "house.fill")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
                .padding(.top, 32)
            Text(lang["loan.empty.title"])
                .font(.headline)
            Text(lang["loan.empty.sub"])
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button { showAdd = true } label: {
                Label(lang["loan.add"], systemImage: "plus")
                    .font(.body.weight(.semibold))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    // MARK: - Actions

    private func archive(_ loan: Loan) {
        loan.isActive.toggle()
        try? context.save()
    }

    private func delete(_ loan: Loan) {
        context.delete(loan)
        try? context.save()
    }
}

// MARK: - Row

struct LoanRow: View {
    let loan: Loan

    private var calc: LoanCalculator { loan.calculator }

    var body: some View {
        HStack(spacing: 12) {
            // Type icon
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 42, height: 42)
                Image(systemName: loan.type.iconSystemName)
                    .foregroundStyle(Color.accentColor)
                    .font(.system(size: 18, weight: .semibold))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(loan.label.isEmpty ? loan.type.label : loan.label)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(loan.lenderName.isEmpty ? loan.currency : loan.lenderName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Text(String(format: "%.2f%%", (loan.annualInterestRate as NSDecimalNumber).doubleValue))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                // Progress bar
                ProgressView(value: calc.progressFraction)
                    .tint(.green)
                    .scaleEffect(y: 0.8)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(Decimal(calc.currentBalance).formatted(asCurrency: loan.currency))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.red)
                Text("\(calc.paymentsRemaining) versements")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
