//
//  CreditLinesView.swift
//  FinTrack
//

import SwiftUI
import SwiftData

struct CreditLinesView: View {
    @Environment(\.modelContext) private var context
    @Environment(LanguageManager.self) private var lang

    @Query(filter: #Predicate<CreditLine> { $0.isActive },
           sort: \CreditLine.createdAt, order: .forward)
    private var activeLines: [CreditLine]

    @Query(filter: #Predicate<CreditLine> { !$0.isActive },
           sort: \CreditLine.createdAt, order: .forward)
    private var archivedLines: [CreditLine]

    @State private var showAdd      = false
    @State private var showArchived = false

    private var debtByCurrency: [(currency: String, total: Decimal)] {
        let grouped = Dictionary(grouping: activeLines, by: \.currency)
        return grouped
            .map { (currency: $0.key, total: $0.value.reduce(Decimal(0)) { $0 + $1.currentBalance }) }
            .filter { ($0.total as NSDecimalNumber).doubleValue > 0 }
            .sorted { $0.currency < $1.currency }
    }

    var body: some View {
        List {
            if activeLines.isEmpty {
                emptyState
            } else {
                // Debt summary
                if !debtByCurrency.isEmpty {
                    Section {
                        ForEach(debtByCurrency, id: \.currency) { row in
                            HStack {
                                Label(lang["cl.totalDebt"] + " (\(row.currency))",
                                      systemImage: "creditcard.trianglebadge.exclamationmark")
                                    .foregroundStyle(.red)
                                Spacer()
                                Text(row.total.formatted(asCurrency: row.currency))
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }

                Section(lang["cl.title"]) {
                    ForEach(activeLines) { cl in
                        NavigationLink {
                            CreditLineDetailView(creditLine: cl)
                        } label: {
                            CreditLineRow(creditLine: cl)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { delete(cl) } label: {
                                Label(lang["action.delete"], systemImage: "trash")
                            }
                            Button { archive(cl) } label: {
                                Label(lang["action.archive"], systemImage: "archivebox")
                            }
                            .tint(.orange)
                        }
                    }
                }
            }

            if !archivedLines.isEmpty {
                Section {
                    DisclosureGroup(isExpanded: $showArchived) {
                        ForEach(archivedLines) { cl in
                            NavigationLink {
                                CreditLineDetailView(creditLine: cl)
                            } label: {
                                CreditLineRow(creditLine: cl).opacity(0.5)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { delete(cl) } label: {
                                    Label(lang["action.delete"], systemImage: "trash")
                                }
                                Button { archive(cl) } label: {
                                    Label(lang["action.resume"], systemImage: "tray.and.arrow.up")
                                }
                                .tint(.green)
                            }
                        }
                    } label: {
                        Text(lang.f("account.archived", archivedLines.count))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(lang["cl.title"])
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: {
                    Image(systemName: "plus.circle.fill").font(.title3)
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddEditCreditLineView(mode: .create)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "creditcard.fill")
                .font(.system(size: 44)).foregroundStyle(.tint).padding(.top, 32)
            Text(lang["cl.empty.title"])
                .font(.headline)
            Text(lang["cl.empty.sub"])
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 24)
            Button { showAdd = true } label: {
                Label(lang["cl.add"], systemImage: "plus")
                    .font(.body.weight(.semibold))
                    .padding(.horizontal, 20).padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent).padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    // MARK: - Actions

    private func archive(_ cl: CreditLine) { cl.isActive.toggle(); try? context.save() }
    private func delete(_ cl: CreditLine)  { context.delete(cl); try? context.save() }
}

// MARK: - Row

struct CreditLineRow: View {
    let creditLine: CreditLine

    var body: some View {
        HStack(spacing: 12) {
            // Utilisation ring
            ZStack {
                Circle()
                    .stroke(Color(.tertiarySystemBackground), lineWidth: 4)
                    .frame(width: 42, height: 42)
                Circle()
                    .trim(from: 0, to: CGFloat(creditLine.utilisationFraction))
                    .stroke(utilisationColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 42, height: 42)
                    .rotationEffect(.degrees(-90))
                Image(systemName: "creditcard.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(utilisationColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(creditLine.name)
                    .font(.body.weight(.medium)).lineLimit(1)
                HStack(spacing: 4) {
                    Text(creditLine.lenderName.isEmpty
                         ? creditLine.currency
                         : creditLine.lenderName)
                        .font(.caption).foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.secondary).font(.caption)
                    Text(String(format: "%.2f%%", (creditLine.annualInterestRate as NSDecimalNumber).doubleValue))
                        .font(.caption).foregroundStyle(.secondary)
                }
                // Mini utilisation bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(.tertiarySystemBackground))
                            .frame(height: 4)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(utilisationColor)
                            .frame(width: geo.size.width * CGFloat(creditLine.utilisationFraction), height: 4)
                    }
                }
                .frame(height: 4)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(creditLine.currentBalance.formatted(asCurrency: creditLine.currency))
                    .font(.body.weight(.semibold)).foregroundStyle(.red)
                Text("/ \(creditLine.creditLimit.formatted(asCurrency: creditLine.currency))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var utilisationColor: Color {
        let u = creditLine.utilisationFraction
        if u >= 0.9 { return .red }
        if u >= 0.7 { return .orange }
        return .green
    }
}
