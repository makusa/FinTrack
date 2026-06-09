//  FinTrackAccessoryWidget.swift — Lock Screen widgets (Circular + Rectangular)
import WidgetKit
import SwiftUI

struct FinTrackAccessoryWidget: Widget {
    let kind = "fintrack.accessory"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FinTrackProvider()) { entry in
            FinTrackAccessoryView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("FinTrack — Écran verrouillé")
        .description("Solde ou résumé du mois sur l'écran verrouillé.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct FinTrackAccessoryView: View {
    let entry: FinTrackEntry
    @Environment(\.widgetFamily) private var family

    private var primary: FinTrackWidgetData.BalanceEntry? {
        entry.data.balances.first(where: { $0.currency == entry.data.primaryCurrency }) ?? entry.data.balances.first
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            VStack(spacing: 1) {
                Image(systemName: "creditcard.fill").font(.caption2)
                if let b = primary {
                    Text(entry.data.formattedShort(b.amount))
                        .font(.caption2.weight(.bold)).minimumScaleFactor(0.5).lineLimit(1)
                    Text(b.currency).font(.system(size: 8)).foregroundStyle(.secondary)
                }
            }
        case .accessoryRectangular:
            HStack(spacing: 6) {
                Image(systemName: "creditcard.fill").font(.caption2)
                VStack(alignment: .leading, spacing: 1) {
                    if let b = primary {
                        Text(entry.data.formatted(b.amount, currency: b.currency))
                            .font(.caption2.weight(.semibold)).lineLimit(1)
                    }
                    HStack(spacing: 4) {
                        Text("+\(entry.data.formattedShort(entry.data.monthIncome))")
                            .font(.system(size: 9)).foregroundStyle(.green)
                        Text("−\(entry.data.formattedShort(entry.data.monthExpense))")
                            .font(.system(size: 9)).foregroundStyle(.red)
                    }
                }
            }
        default: // accessoryInline
            if let b = primary {
                Text("💳 \(entry.data.formattedShort(b.amount)) \(b.symbol)")
            }
        }
    }
}
