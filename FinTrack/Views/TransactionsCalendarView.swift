//
//  TransactionsCalendarView.swift
//  FinTrack
//
//  Calendar view of transactions: real (past, editable) + planned
//  (future occurrences projected from recurring rules, loan payments,
//  and scheduled prepayments). Month navigation past/future.
//

import SwiftUI
import SwiftData

// MARK: - Unified calendar item (real or planned)

struct CalendarItem: Identifiable {
    enum PlannedKind {
        case recurring, loanPayment, prepayment
    }

    let id: String
    let date: Date
    let label: String
    let sublabel: String
    let amount: Decimal
    let currency: String
    let isIncome: Bool
    let plannedKind: PlannedKind?          // nil = real transaction
    let transaction: Transaction?          // set when real, for editing

    var isPlanned: Bool { plannedKind != nil }
}

// MARK: - Calendar view

struct TransactionsCalendarView: View {
    @Environment(LanguageManager.self) private var lang

    let realTransactions: [Transaction]
    let typeFilter: TransactionsView.TypeFilter
    let accountFilter: Account?

    @Query(filter: #Predicate<RecurringTransaction> { $0.isActive })
    private var activeRecurring: [RecurringTransaction]

    @Query(filter: #Predicate<Loan> { $0.isActive })
    private var activeLoans: [Loan]

    @Query private var allPrepayments: [LoanPrepayment]

    /// Prepayments still pending — one-time already posted use the
    /// nextPostDate == .distantFuture sentinel (see LoanPrepaymentManager).
    private var activePrepayments: [LoanPrepayment] {
        allPrepayments.filter { ($0.nextPostDate ?? .now) != .distantFuture }
    }

    enum SourceFilter: String, CaseIterable, Identifiable {
        case all, real, planned
        var id: String { rawValue }
        func label(using lang: LanguageManager) -> String {
            switch self {
            case .all:     return lang["label.all"]
            case .real:    return lang["calendar.source.real"]
            case .planned: return lang["calendar.source.planned"]
            }
        }
    }

    @State private var displayedMonth: Date = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
    @State private var selectedDay: Date = Calendar.current.startOfDay(for: .now)
    @State private var sourceFilter: SourceFilter = .all

    private var cal: Calendar { Calendar.current }

    // MARK: Month items (real + planned), grouped by day

    private var monthInterval: DateInterval {
        cal.dateInterval(of: .month, for: displayedMonth) ?? DateInterval(start: displayedMonth, duration: 0)
    }

    private var itemsByDay: [Date: [CalendarItem]] {
        var items: [CalendarItem] = []
        let interval = monthInterval
        let today = cal.startOfDay(for: .now)

        // ── Real transactions in the displayed month ──────────────────────
        if sourceFilter != .planned {
            for tx in realTransactions where interval.contains(tx.date) {
                if !matchesFilters(type: tx.type, account: tx.account) { continue }
                items.append(CalendarItem(
                    id: "tx-\(tx.persistentModelID.hashValue)",
                    date: tx.date,
                    label: tx.payee ?? tx.category?.localizedName ?? tx.type.label,
                    sublabel: tx.account?.name ?? "",
                    amount: tx.amount,
                    currency: tx.account?.currency ?? Currencies.default,
                    isIncome: tx.type == .income,
                    plannedKind: nil,
                    transaction: tx
                ))
            }
        }

        // ── Planned occurrences (future only — past is materialised) ──────
        if sourceFilter != .real {
            // 1. Recurring rules
            for rule in activeRecurring {
                // Les paiements de prêt sont déjà projetés via l'amortissement (section 2) ;
                // on saute ici leur règle génératrice pour éviter le doublon.
                if rule.isLoanPayment { continue }
                if !matchesFilters(type: rule.type, account: rule.account) { continue }
                var d = rule.nextDueDate
                var guardCount = 0
                while d <= interval.end && guardCount < 62 {
                    if let end = rule.endDate, d > end { break }
                    if d >= max(interval.start, today) && d < interval.end {
                        items.append(CalendarItem(
                            id: "rec-\(rule.persistentModelID.hashValue)-\(Int(d.timeIntervalSince1970))",
                            date: d,
                            label: rule.displayTitle,
                            sublabel: lang["calendar.kind.recurring"],
                            amount: rule.amount,
                            currency: rule.account?.currency ?? Currencies.default,
                            isIncome: rule.type == .income,
                            plannedKind: .recurring,
                            transaction: nil
                        ))
                    }
                    d = rule.frequency.nextDate(after: d)
                    guardCount += 1
                }
            }

            // 2. Loan payments
            if typeFilter != .income {
                for loan in activeLoans {
                    if let acc = accountFilter, loan.account?.persistentModelID != acc.persistentModelID { continue }
                    let from = loan.calculator.paymentsElapsedToday + 1
                    let to = loan.calculator.effectivePayments
                    guard from <= to else { continue }
                    for k in from...to {
                        let d = loan.calculator.paymentDate(k)
                        if d < max(interval.start, today) { continue }
                        if d >= interval.end { break }
                        items.append(CalendarItem(
                            id: "loan-\(loan.persistentModelID.hashValue)-\(k)",
                            date: d,
                            label: loan.label.isEmpty ? loan.lenderName : loan.label,
                            sublabel: lang["calendar.kind.loan"],
                            amount: Decimal(loan.calculator.paymentAmount),
                            currency: loan.currency,
                            isIncome: false,
                            plannedKind: .loanPayment,
                            transaction: nil
                        ))
                    }
                }
            }

            // 3. Scheduled prepayments
            if typeFilter != .income {
                for prep in activePrepayments {
                    guard let loan = prep.loan else { continue }
                    if let acc = accountFilter, prep.account?.persistentModelID != acc.persistentModelID { continue }
                    let label = loan.label.isEmpty ? loan.lenderName : loan.label
                    if prep.isRecurring, let freq = prep.frequency {
                        var d = prep.nextPostDate ?? prep.startDate
                        var guardCount = 0
                        while d <= interval.end && guardCount < 62 {
                            if let end = prep.endDate, d > end { break }
                            if d >= max(interval.start, today) && d < interval.end {
                                items.append(plannedPrepaymentItem(prep, loan: label, date: d))
                            }
                            d = freq.nextDate(after: d)
                            guardCount += 1
                        }
                    } else {
                        let d = prep.startDate
                        if d >= max(interval.start, today) && d < interval.end {
                            items.append(plannedPrepaymentItem(prep, loan: label, date: d))
                        }
                    }
                }
            }
        }

        return Dictionary(grouping: items) { cal.startOfDay(for: $0.date) }
    }

    private func plannedPrepaymentItem(_ prep: LoanPrepayment, loan: String, date: Date) -> CalendarItem {
        CalendarItem(
            id: "prep-\(prep.persistentModelID.hashValue)-\(Int(date.timeIntervalSince1970))",
            date: date,
            label: loan,
            sublabel: lang["calendar.kind.prepayment"],
            amount: prep.amount,
            currency: prep.loan?.currency ?? Currencies.default,
            isIncome: false,
            plannedKind: .prepayment,
            transaction: nil
        )
    }

    private func matchesFilters(type: TransactionType, account: Account?) -> Bool {
        switch typeFilter {
        case .all: break
        case .income:  if type != .income  { return false }
        case .expense: if type != .expense { return false }
        }
        if let acc = accountFilter, account?.persistentModelID != acc.persistentModelID { return false }
        return true
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            monthHeader
            sourcePicker
            weekdayHeader
            monthGrid
            Divider()
            dayList
        }
    }

    // MARK: Header — month navigation

    private var monthHeader: some View {
        HStack {
            Button { shiftMonth(-1) } label: {
                Image(systemName: "chevron.left").font(.body.weight(.semibold))
            }
            Spacer()
            VStack(spacing: 2) {
                Text(displayedMonth.appFormattedMonthYear())
                    .font(.headline)
                if !cal.isDate(displayedMonth, equalTo: .now, toGranularity: .month) {
                    Button(lang["calendar.today"]) { goToToday() }
                        .font(.caption2)
                }
            }
            Spacer()
            Button { shiftMonth(1) } label: {
                Image(systemName: "chevron.right").font(.body.weight(.semibold))
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var sourcePicker: some View {
        Picker(lang["calendar.source"], selection: $sourceFilter) {
            ForEach(SourceFilter.allCases) { f in
                Text(f.label(using: lang)).tag(f)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    // MARK: Weekday header (locale-aware first weekday)

    private var orderedWeekdaySymbols: [String] {
        let symbols = cal.veryShortStandaloneWeekdaySymbols  // [dim, lun, …] index 0 = Sunday
        let first = cal.firstWeekday - 1                     // 0-based
        return Array(symbols[first...] + symbols[..<first])
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(Array(orderedWeekdaySymbols.enumerated()), id: \.offset) { _, s in
                Text(s)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.bottom, 4)
    }

    // MARK: Month grid

    private var gridDays: [Date?] {
        let interval = monthInterval
        let firstDay = interval.start
        let weekdayOfFirst = cal.component(.weekday, from: firstDay)      // 1 = Sunday
        let leading = (weekdayOfFirst - cal.firstWeekday + 7) % 7
        let dayCount = cal.range(of: .day, in: .month, for: firstDay)?.count ?? 30

        var days: [Date?] = Array(repeating: nil, count: leading)
        for d in 0..<dayCount {
            days.append(cal.date(byAdding: .day, value: d, to: firstDay))
        }
        return days
    }

    private var monthGrid: some View {
        let byDay = itemsByDay
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(Array(gridDays.enumerated()), id: \.offset) { _, day in
                if let day {
                    dayCell(day, items: byDay[cal.startOfDay(for: day)] ?? [])
                } else {
                    Color.clear.frame(height: 44)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
        .gesture(
            DragGesture(minimumDistance: 30).onEnded { value in
                if value.translation.width < -30 { shiftMonth(1) }
                else if value.translation.width > 30 { shiftMonth(-1) }
            }
        )
    }

    private func dayCell(_ day: Date, items: [CalendarItem]) -> some View {
        let isSelected = cal.isDate(day, inSameDayAs: selectedDay)
        let isToday = cal.isDateInToday(day)
        let hasIncome  = items.contains { $0.isIncome && !$0.isPlanned }
        let hasExpense = items.contains { !$0.isIncome && !$0.isPlanned }
        let hasPlanned = items.contains { $0.isPlanned }

        return Button {
            selectedDay = cal.startOfDay(for: day)
        } label: {
            VStack(spacing: 3) {
                Text("\(cal.component(.day, from: day))")
                    .font(.callout.weight(isToday ? .bold : .regular))
                    .foregroundStyle(
                        isSelected ? AnyShapeStyle(Color.white) :
                        isToday    ? AnyShapeStyle(Color.accentColor) :
                                     AnyShapeStyle(Color.primary)
                    )
                HStack(spacing: 3) {
                    if hasIncome  { Circle().fill(Color.green).frame(width: 5, height: 5) }
                    if hasExpense { Circle().fill(Color.red).frame(width: 5, height: 5) }
                    if hasPlanned { Circle().fill(Color.orange).frame(width: 5, height: 5) }
                }
                .frame(height: 6)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                isSelected ? Color.accentColor : Color.clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Day detail list

    private var dayList: some View {
        let items = (itemsByDay[selectedDay] ?? []).sorted { $0.date < $1.date }
        return List {
            Section(selectedDay.appFormattedLong()) {
                if items.isEmpty {
                    Text(lang["calendar.noTransactions"])
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(items) { item in
                        if let tx = item.transaction {
                            NavigationLink {
                                AddEditTransactionView(mode: .edit(tx))
                            } label: {
                                calendarRow(item)
                            }
                        } else {
                            calendarRow(item)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func calendarRow(_ item: CalendarItem) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(rowColor(item).opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: rowIcon(item))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(rowColor(item))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.label)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if item.isPlanned {
                        Text(lang["calendar.planned"])
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.orange.opacity(0.15), in: Capsule())
                            .foregroundStyle(Color.orange)
                    }
                    if !item.sublabel.isEmpty {
                        Text(item.sublabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer()
            Text((item.isIncome ? "+" : "−") + item.amount.formatted(asCurrency: item.currency))
                .font(.body.weight(.semibold))
                .foregroundStyle(
                    item.isPlanned ? AnyShapeStyle(Color.secondary) :
                    item.isIncome  ? AnyShapeStyle(Color.green) :
                                     AnyShapeStyle(Color.primary)
                )
                .opacity(item.isPlanned ? 0.8 : 1)
        }
        .padding(.vertical, 2)
    }

    private func rowColor(_ item: CalendarItem) -> Color {
        if item.isPlanned { return .orange }
        return item.isIncome ? .green : .red
    }

    private func rowIcon(_ item: CalendarItem) -> String {
        switch item.plannedKind {
        case .recurring:   return "repeat"
        case .loanPayment: return "building.columns"
        case .prepayment:  return "arrow.down.to.line"
        case nil:          return item.isIncome ? "arrow.down.left" : "arrow.up.right"
        }
    }

    // MARK: Navigation helpers

    private func shiftMonth(_ delta: Int) {
        guard let newMonth = cal.date(byAdding: .month, value: delta, to: displayedMonth) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            displayedMonth = newMonth
            // Keep selection inside the displayed month
            if !cal.isDate(selectedDay, equalTo: newMonth, toGranularity: .month) {
                selectedDay = cal.startOfDay(for: newMonth)
            }
        }
    }

    private func goToToday() {
        withAnimation(.easeInOut(duration: 0.2)) {
            displayedMonth = cal.dateInterval(of: .month, for: .now)?.start ?? .now
            selectedDay = cal.startOfDay(for: .now)
        }
    }
}
