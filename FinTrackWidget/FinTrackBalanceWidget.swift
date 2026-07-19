//  FinTrackBalanceWidget.swift — Configurable Home widget (net worth / budgets / …)
//  Unified "Focus" look: side accent, hero number, coloured bars.
import WidgetKit
import SwiftUI
import AppIntents

struct FinTrackBalanceWidget: Widget {
    let kind = "fintrack.balance"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectContentIntent.self, provider: FinTrackConfigProvider()) { entry in
            FinTrackBalanceView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("FinTrack")
        .description("Net worth, budgets and the month at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct FinTrackBalanceView: View {
    let entry: FinTrackEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        switch entry.content {
        case .netWorth:
            switch family {
            case .systemSmall:  SmallBalanceView(data: entry.data)
            case .systemMedium: MediumBalanceView(data: entry.data)
            default:            LargeBalanceView(data: entry.data)
            }
        case .budgets:
            switch family {
            case .systemSmall:  SmallBudgetsView(data: entry.data)
            case .systemMedium: MediumBudgetsView(data: entry.data)
            default:            LargeBudgetsView(data: entry.data)
            }
        case .balances:
            switch family {
            case .systemSmall:  SmallAccountsView(data: entry.data)
            case .systemMedium: MediumAccountsView(data: entry.data)
            default:            LargeAccountsView(data: entry.data)
            }
        case .savings:
            switch family {
            case .systemSmall:  SmallSavingsView(data: entry.data)
            case .systemMedium: MediumSavingsView(data: entry.data)
            default:            LargeSavingsView(data: entry.data)
            }
        case .registered:
            switch family {
            case .systemSmall:  SmallRegisteredView(data: entry.data)
            case .systemMedium: MediumRegisteredView(data: entry.data)
            default:            LargeRegisteredView(data: entry.data)
            }
        }
    }
}

// MARK: - Small  (Focus: net-worth hero + month change + side accent)

struct SmallBalanceView: View {
    let data: FinTrackWidgetData
    var body: some View {
        HStack(spacing: 0) {
            SideAccent(color: trendColor(data.netWorthMonthChange))
            VStack(alignment: .leading, spacing: 0) {
                WidgetCaption(text: data.str("netWorth"))
                Spacer(minLength: 4)
                HeroAmount(data: data, amount: data.netWorth, style: .largeTitle)
                Spacer(minLength: 4)
                TrendPill(data: data)
            }
            .padding(.leading, 11)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .padding(14)
    }
}

// MARK: - Medium  (Focus left: net worth + change + balances | right: month bar)

struct MediumBalanceView: View {
    let data: FinTrackWidgetData
    var body: some View {
        HStack(spacing: 0) {
            SideAccent(color: trendColor(data.netWorthMonthChange))

            VStack(alignment: .leading, spacing: 5) {
                WidgetCaption(text: data.str("netWorth"))
                HeroAmount(data: data, amount: data.netWorth, style: .title2)
                TrendPill(data: data)
                Spacer(minLength: 0)
                ForEach(data.balances.prefix(2)) { b in
                    HStack {
                        Text(b.currency).font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        Text(data.formattedSigned(b.amount))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(b.amount >= 0 ? Color.primary : Color.red)
                    }
                }
            }
            .padding(.leading, 11).padding(.vertical, 14).padding(.trailing, 6)
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider().padding(.vertical, 14)

            VStack(alignment: .leading, spacing: 6) {
                WidgetCaption(text: data.str("thisMonth"))
                MonthBar(income: data.monthIncome, expense: data.monthExpense).frame(height: 7)
                HStack(spacing: 4) {
                    Circle().fill(.green).frame(width: 6, height: 6)
                    Text("+\(data.formattedShort(data.monthIncome))")
                        .font(.caption2.weight(.medium)).foregroundStyle(.green)
                    Spacer()
                }
                HStack(spacing: 4) {
                    Circle().fill(.red).frame(width: 6, height: 6)
                    Text("−\(data.formattedShort(data.monthExpense))")
                        .font(.caption2.weight(.medium)).foregroundStyle(.red)
                    Spacer()
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 14).padding(.trailing, 14).padding(.leading, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Large  (Focus header + month bar + registered room + recent + upcoming)

struct LargeBalanceView: View {
    let data: FinTrackWidgetData
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Focus header
            HStack(spacing: 0) {
                SideAccent(color: trendColor(data.netWorthMonthChange))
                VStack(alignment: .leading, spacing: 2) {
                    WidgetCaption(text: data.str("netWorth"))
                    HeroAmount(data: data, amount: data.netWorth, style: .title)
                }
                .padding(.leading, 10)
                Spacer()
                TrendPill(data: data)
            }
            .padding([.horizontal, .top])

            // Month bar
            MonthBar(income: data.monthIncome, expense: data.monthExpense)
                .frame(height: 7).padding(.horizontal).padding(.top, 8)
            HStack(spacing: 10) {
                Label("+\(data.formattedShort(data.monthIncome))", systemImage: "arrow.down.left")
                    .font(.caption2).foregroundStyle(.green)
                Label("−\(data.formattedShort(data.monthExpense))", systemImage: "arrow.up.right")
                    .font(.caption2).foregroundStyle(.red)
                Spacer()
            }.padding(.horizontal).padding(.top, 3)

            // Registered-account room
            if !data.registeredRooms.isEmpty {
                Divider().padding(.horizontal).padding(.top, 8)
                ForEach(data.registeredRooms.prefix(2)) { room in
                    VStack(spacing: 2) {
                        HStack {
                            Text(room.shortName).font(.caption2.weight(.semibold))
                            Spacer()
                            Text("\(data.formattedSigned(room.available)) \(data.str("available"))")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(room.isOver ? .red : .green)
                        }
                        ProgressView(value: room.usedFraction)
                            .tint(room.isOver ? .red : .accentColor)
                    }.padding(.horizontal).padding(.top, 3)
                }
            }

            // Recent
            if !data.recentTransactions.isEmpty {
                Divider().padding(.horizontal).padding(.top, 8)
                WidgetCaption(text: data.str("recent")).padding(.horizontal).padding(.top, 3)
                ForEach(data.recentTransactions.prefix(3)) { tx in
                    HStack(spacing: 6) {
                        Image(systemName: tx.isIncome ? "arrow.down.left" : "arrow.up.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(tx.isIncome ? Color.green : Color.secondary).frame(width: 12)
                        Text(tx.label).font(.caption2).lineLimit(1)
                        Spacer()
                        Text((tx.isIncome ? "+" : "−") + data.formattedShort(tx.amount))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(tx.isIncome ? Color.green : Color.primary)
                    }.padding(.horizontal).padding(.vertical, 1)
                }
            }

            // Upcoming
            if !data.upcoming.isEmpty {
                Divider().padding(.horizontal).padding(.top, 8)
                WidgetCaption(text: data.str("upcoming")).padding(.horizontal).padding(.top, 3)
                ForEach(data.upcoming.prefix(2)) { ev in
                    HStack(spacing: 6) {
                        Image(systemName: "calendar").font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.orange).frame(width: 12)
                        Text(ev.name).font(.caption2).lineLimit(1)
                        Spacer()
                        Text(ev.daysUntil == 0 ? data.str("today") : "J+\(ev.daysUntil)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(ev.daysUntil <= 2 ? Color.orange : Color.secondary)
                    }.padding(.horizontal).padding(.vertical, 1)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Budgets content

private struct BudgetRow: View {
    let data: FinTrackWidgetData
    let budget: FinTrackWidgetData.WidgetBudget
    var showLimit: Bool = false
    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Text(budget.name).font(.caption2.weight(.semibold)).lineLimit(1)
                Spacer()
                if showLimit {
                    Text("\(data.formattedMoney(budget.spent, currency: budget.currency)) / \(data.formattedMoney(budget.limit, currency: budget.currency))")
                        .font(.system(.caption2, design: .rounded).weight(.medium))
                        .foregroundStyle(budget.isOver ? .red : .secondary)
                        .lineLimit(1).minimumScaleFactor(0.6)
                } else {
                    Text(data.formattedMoney(budget.spent, currency: budget.currency))
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .foregroundStyle(budget.isOver ? .red : .primary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            ProgressView(value: budget.fraction).tint(budget.isOver ? .red : Color(widgetHex: budget.colorHex))
        }
    }
}

private struct BudgetsList: View {
    let data: FinTrackWidgetData
    let maxCount: Int
    let showLimit: Bool
    private var accent: Color { data.budgets.contains(where: { $0.isOver }) ? .red : .green }
    var body: some View {
        HStack(spacing: 0) {
            SideAccent(color: accent)
            VStack(alignment: .leading, spacing: showLimit ? 7 : 6) {
                WidgetCaption(text: data.str("budgets"))
                if data.budgets.isEmpty {
                    Spacer()
                    Text(data.str("noData")).font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                } else {
                    ForEach(data.budgets.prefix(maxCount)) { b in
                        BudgetRow(data: data, budget: b, showLimit: showLimit)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(.leading, 11)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .padding(14)
    }
}

// Small is too tight for names + full amounts, so it shows just the budget's
// icon and the abbreviated amount spent, with its progress bar.
struct SmallBudgetsView: View {
    let data: FinTrackWidgetData
    private var accent: Color { data.budgets.contains(where: { $0.isOver }) ? .red : .green }
    var body: some View {
        HStack(spacing: 0) {
            SideAccent(color: accent)
            VStack(alignment: .leading, spacing: 7) {
                WidgetCaption(text: data.str("budgets"))
                if data.budgets.isEmpty {
                    Spacer()
                    Text(data.str("noData")).font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                } else {
                    ForEach(data.budgets.prefix(3)) { b in
                        VStack(spacing: 3) {
                            HStack {
                                Image(systemName: b.icon).font(.caption)
                                    .foregroundStyle(b.isOver ? .red : Color(widgetHex: b.colorHex))
                                Spacer()
                                Text(data.formattedShortMoney(b.spent, currency: b.currency))
                                    .font(.system(.caption, design: .rounded).weight(.bold))
                                    .foregroundStyle(b.isOver ? .red : .primary)
                                    .lineLimit(1).minimumScaleFactor(0.8)
                            }
                            ProgressView(value: b.fraction).tint(b.isOver ? .red : Color(widgetHex: b.colorHex))
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(.leading, 11)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .padding(14)
    }
}

struct MediumBudgetsView: View {
    let data: FinTrackWidgetData
    var body: some View { BudgetsList(data: data, maxCount: 4, showLimit: true) }
}

struct LargeBudgetsView: View {
    let data: FinTrackWidgetData
    private var accent: Color { data.budgets.contains(where: { $0.isOver }) ? .red : .green }
    var body: some View {
        HStack(spacing: 0) {
            SideAccent(color: accent)
            VStack(alignment: .leading, spacing: 6) {
                WidgetCaption(text: data.str("budgets"))
                if data.budgets.isEmpty {
                    Spacer()
                    Text(data.str("noData")).font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                } else {
                    ForEach(data.budgets.prefix(4)) { b in
                        BudgetRow(data: data, budget: b, showLimit: true)
                    }
                    if !data.budgetTransactions.isEmpty {
                        Divider().padding(.vertical, 3)
                        WidgetCaption(text: data.str("recent"))
                        ForEach(data.budgetTransactions.prefix(4)) { tx in
                            HStack(spacing: 6) {
                                Circle().fill(Color(widgetHex: tx.colorHex)).frame(width: 7, height: 7)
                                Text(tx.label).font(.caption2).lineLimit(1)
                                Spacer()
                                Text("−\(data.formattedMoney(tx.amount, currency: tx.currency))")
                                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1).minimumScaleFactor(0.75)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(.leading, 11).padding(.vertical, 14).padding(.trailing, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Account balances content

private struct AccountRow: View {
    let data: FinTrackWidgetData
    let account: FinTrackWidgetData.WidgetAccount
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: account.icon)
                .font(.caption2)
                .foregroundStyle(Color(widgetHex: account.colorHex))
                .frame(width: 15)
            Text(account.name).font(.caption2.weight(.medium)).lineLimit(1)
            Spacer()
            Text(data.formattedMoney(account.balance, currency: account.currency))
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .foregroundStyle(account.balance < 0 ? .red : .primary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
    }
}

private struct AccountsList: View {
    let data: FinTrackWidgetData
    let maxCount: Int
    private var accent: Color {
        data.accounts.reduce(0.0) { $0 + $1.balance } >= 0 ? .green : .orange
    }
    var body: some View {
        HStack(spacing: 0) {
            SideAccent(color: accent)
            VStack(alignment: .leading, spacing: 6) {
                WidgetCaption(text: data.str("balances"))
                if data.accounts.isEmpty {
                    Spacer()
                    Text(data.str("noData")).font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                } else {
                    ForEach(data.accounts.prefix(maxCount)) { a in
                        AccountRow(data: data, account: a)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(.leading, 11)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .padding(14)
    }
}

// Small is too tight for the per-account list, so it shows the combined total
// as a hero; the detailed list lives in Medium and Large.
struct SmallAccountsView: View {
    let data: FinTrackWidgetData
    var body: some View {
        HStack(spacing: 0) {
            SideAccent(color: data.accountsTotal >= 0 ? .green : .orange)
            VStack(alignment: .leading, spacing: 0) {
                WidgetCaption(text: data.str("balances"))
                Spacer(minLength: 4)
                HeroAmount(data: data, amount: data.accountsTotal, style: .largeTitle)
                Spacer(minLength: 4)
            }
            .padding(.leading, 11)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .padding(14)
    }
}

struct MediumAccountsView: View {
    let data: FinTrackWidgetData
    var body: some View { AccountsList(data: data, maxCount: 5) }
}

struct LargeAccountsView: View {
    let data: FinTrackWidgetData
    var body: some View { AccountsList(data: data, maxCount: 8) }
}

// MARK: - Savings goals content

private struct SavingsRow: View {
    let data: FinTrackWidgetData
    let project: FinTrackWidgetData.WidgetSavings
    var showTarget: Bool = false
    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: project.icon).font(.caption2)
                    .foregroundStyle(Color(widgetHex: project.colorHex)).frame(width: 13)
                Text(project.name).font(.caption2.weight(.semibold)).lineLimit(1)
                Spacer()
                if showTarget, let t = project.target {
                    Text("\(data.formattedMoney(project.current, currency: project.currency)) / \(data.formattedMoney(t, currency: project.currency))")
                        .font(.system(.caption2, design: .rounded).weight(.medium))
                        .foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.6)
                } else {
                    Text(data.formattedMoney(project.current, currency: project.currency))
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            if project.hasTarget {
                ProgressView(value: project.fraction).tint(Color(widgetHex: project.colorHex))
            }
        }
    }
}

private struct SavingsList: View {
    let data: FinTrackWidgetData
    let maxCount: Int
    let showTarget: Bool
    var body: some View {
        HStack(spacing: 0) {
            SideAccent(color: .green)
            VStack(alignment: .leading, spacing: showTarget ? 7 : 6) {
                WidgetCaption(text: data.str("savings"))
                if data.savings.isEmpty {
                    Spacer()
                    Text(data.str("noData")).font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                } else {
                    ForEach(data.savings.prefix(maxCount)) { p in
                        SavingsRow(data: data, project: p, showTarget: showTarget)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(.leading, 11)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .padding(14)
    }
}

// Small is too tight for names + full amounts, so it shows just the project's
// icon and an abbreviated amount (e.g. "4,5k $ CA") with its progress bar.
struct SmallSavingsView: View {
    let data: FinTrackWidgetData
    var body: some View {
        HStack(spacing: 0) {
            SideAccent(color: .green)
            VStack(alignment: .leading, spacing: 7) {
                WidgetCaption(text: data.str("savings"))
                if data.savings.isEmpty {
                    Spacer()
                    Text(data.str("noData")).font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                } else {
                    ForEach(data.savings.prefix(3)) { p in
                        VStack(spacing: 3) {
                            HStack {
                                Image(systemName: p.icon).font(.caption)
                                    .foregroundStyle(Color(widgetHex: p.colorHex))
                                Spacer()
                                Text(data.formattedShortMoney(p.current, currency: p.currency))
                                    .font(.system(.caption, design: .rounded).weight(.bold))
                                    .lineLimit(1).minimumScaleFactor(0.8)
                            }
                            if p.hasTarget {
                                ProgressView(value: p.fraction).tint(Color(widgetHex: p.colorHex))
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(.leading, 11)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .padding(14)
    }
}

struct MediumSavingsView: View {
    let data: FinTrackWidgetData
    var body: some View { SavingsList(data: data, maxCount: 4, showTarget: true) }
}

struct LargeSavingsView: View {
    let data: FinTrackWidgetData
    var body: some View { SavingsList(data: data, maxCount: 6, showTarget: true) }
}

// MARK: - Registered accounts content (contribution room)

private struct RegisteredRow: View {
    let data: FinTrackWidgetData
    let room: FinTrackWidgetData.RegisteredRoomEntry
    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Text(room.shortName).font(.caption2.weight(.semibold))
                Spacer()
                Text(data.formattedMoney(room.available, currency: "CAD"))
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .foregroundStyle(room.isOver ? .red : .green)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            ProgressView(value: room.usedFraction).tint(room.isOver ? .red : .accentColor)
        }
    }
}

private struct RegisteredList: View {
    let data: FinTrackWidgetData
    private var accent: Color { data.registeredRooms.contains(where: { $0.isOver }) ? .red : .green }
    var body: some View {
        HStack(spacing: 0) {
            SideAccent(color: accent)
            VStack(alignment: .leading, spacing: 7) {
                WidgetCaption(text: data.str("room"))
                if data.registeredRooms.isEmpty {
                    Spacer()
                    Text(data.str("noData")).font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                } else {
                    ForEach(data.registeredRooms) { room in
                        RegisteredRow(data: data, room: room)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(.leading, 11)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .padding(14)
    }
}

struct SmallRegisteredView: View {
    let data: FinTrackWidgetData
    var body: some View { RegisteredList(data: data) }
}

struct MediumRegisteredView: View {
    let data: FinTrackWidgetData
    var body: some View { RegisteredList(data: data) }
}

struct LargeRegisteredView: View {
    let data: FinTrackWidgetData
    var body: some View { RegisteredList(data: data) }
}
