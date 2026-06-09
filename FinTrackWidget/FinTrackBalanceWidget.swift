//  FinTrackBalanceWidget.swift — Small / Medium / Large home screen widgets
import WidgetKit
import SwiftUI

struct FinTrackBalanceWidget: Widget {
    let kind = "fintrack.balance"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FinTrackProvider()) { entry in
            FinTrackBalanceView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Solde FinTrack")
        .description("Affiche vos soldes et le résumé du mois.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct FinTrackBalanceView: View {
    let entry: FinTrackEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        switch family {
        case .systemSmall:  SmallBalanceView(data: entry.data)
        case .systemMedium: MediumBalanceView(data: entry.data)
        default:            LargeBalanceView(data: entry.data)
        }
    }
}

// MARK: - Small
struct SmallBalanceView: View {
    let data: FinTrackWidgetData
    private var primary: FinTrackWidgetData.BalanceEntry? {
        data.balances.first(where: { $0.currency == data.primaryCurrency }) ?? data.balances.first
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "creditcard.fill").font(.caption).foregroundStyle(.tint)
                Text("FinTrack").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            }
            Spacer()
            if let b = primary {
                Text(data.formattedShort(b.amount))
                    .font(.title2.weight(.bold)).minimumScaleFactor(0.6).lineLimit(1)
                    .foregroundStyle(b.amount >= 0 ? Color.primary : Color.red)
                Text("\(b.symbol) · Solde").font(.caption2).foregroundStyle(.secondary)
            } else {
                Text("—").font(.title2.weight(.bold))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading).padding()
    }
}

// MARK: - Medium
struct MediumBalanceView: View {
    let data: FinTrackWidgetData
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Soldes", systemImage: "building.columns.fill")
                    .font(.caption2.weight(.semibold)).foregroundStyle(.tint)
                Spacer(minLength: 0)
                ForEach(data.balances.prefix(3)) { b in
                    HStack {
                        Text(b.currency).font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        Text(data.formattedShort(b.amount))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(b.amount >= 0 ? Color.primary : Color.red)
                    }
                }
            }.padding().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            Divider().padding(.vertical, 10)
            VStack(alignment: .leading, spacing: 6) {
                Text("Ce mois").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Label(data.formattedShort(data.monthIncome), systemImage: "arrow.down.left.circle.fill")
                    .font(.caption2).foregroundStyle(Color.green)
                Label(data.formattedShort(data.monthExpense), systemImage: "arrow.up.right.circle.fill")
                    .font(.caption2).foregroundStyle(Color.red)
                let net = data.monthIncome - data.monthExpense
                Label(data.formattedShort(net), systemImage: net >= 0 ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.caption2.weight(.bold)).foregroundStyle(net >= 0 ? Color.accentColor : Color.orange)
            }.padding().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Large
struct LargeBalanceView: View {
    let data: FinTrackWidgetData
    private var primaryAmount: Double {
        data.balances.first(where: { $0.currency == data.primaryCurrency })?.amount ?? 0
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("FinTrack", systemImage: "creditcard.fill")
                    .font(.caption.weight(.semibold)).foregroundStyle(.tint)
                Spacer()
                Text(data.formatted(primaryAmount, currency: data.primaryCurrency))
                    .font(.caption.weight(.bold))
            }.padding([.horizontal, .top])
            Divider().padding(.horizontal)
            HStack(spacing: 12) {
                Label(data.formattedShort(data.monthIncome), systemImage: "arrow.down.left.circle.fill")
                    .font(.caption2).foregroundStyle(Color.green)
                Label(data.formattedShort(data.monthExpense), systemImage: "arrow.up.right.circle.fill")
                    .font(.caption2).foregroundStyle(Color.red)
                Spacer()
            }.padding(.horizontal).padding(.vertical, 6)
            if !data.recentTransactions.isEmpty {
                Divider().padding(.horizontal)
                Text("Récentes").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    .padding(.horizontal).padding(.top, 4)
                ForEach(data.recentTransactions.prefix(4)) { tx in
                    HStack {
                        Image(systemName: tx.isIncome ? "arrow.down.left" : "arrow.up.right")
                            .font(.caption2).foregroundStyle(tx.isIncome ? Color.green : Color.secondary).frame(width: 14)
                        Text(tx.label).font(.caption2).lineLimit(1)
                        Spacer()
                        Text((tx.isIncome ? "+" : "−") + data.formattedShort(tx.amount))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(tx.isIncome ? Color.green : Color.primary)
                    }.padding(.horizontal).padding(.vertical, 2)
                }
            }
            if !data.upcoming.isEmpty {
                Divider().padding(.horizontal).padding(.top, 4)
                Text("À venir").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    .padding(.horizontal).padding(.top, 4)
                ForEach(data.upcoming.prefix(3)) { ev in
                    HStack {
                        Image(systemName: "calendar").font(.caption2).foregroundStyle(Color.orange).frame(width: 14)
                        Text(ev.name).font(.caption2).lineLimit(1)
                        Spacer()
                        Text(ev.daysUntil == 0 ? "Auj." : "J+\(ev.daysUntil)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(ev.daysUntil <= 2 ? Color.orange : Color.secondary)
                    }.padding(.horizontal).padding(.vertical, 2)
                }
            }
            Spacer(minLength: 0)
        }
    }
}
