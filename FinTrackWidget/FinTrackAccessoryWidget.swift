//  FinTrackAccessoryWidget.swift — Lock Screen widgets (Circular + Rectangular + Inline)
//  Same "Focus" idea, adapted to the Lock Screen: net-worth hero + month-change
//  trend. No side accent here — Lock Screen renders tinted/monochrome.
import WidgetKit
import SwiftUI

struct FinTrackAccessoryWidget: Widget {
    let kind = "fintrack.accessory"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FinTrackProvider()) { entry in
            FinTrackAccessoryView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("FinTrack — Lock Screen")
        .description("Net worth, month trend or contribution room.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct FinTrackAccessoryView: View {
    let entry: FinTrackEntry
    @Environment(\.widgetFamily) private var family

    private var data: FinTrackWidgetData { entry.data }
    private var symbol: String {
        data.balances.first(where: { $0.currency == data.primaryCurrency })?.symbol ?? data.primaryCurrency
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            // Prefer a contribution-room gauge (the differentiator); fall back to net worth.
            if let room = data.registeredRooms.first {
                Gauge(value: room.usedFraction) {
                    Text(room.shortName)
                } currentValueLabel: {
                    Text(data.formattedShort(room.available)).minimumScaleFactor(0.5)
                }
                .gaugeStyle(.accessoryCircular)
                .tint(room.isOver ? .red : .green)
            } else {
                VStack(spacing: 1) {
                    Image(systemName: "chart.pie.fill").font(.caption2)
                    Text(data.formattedSigned(data.netWorth))
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .minimumScaleFactor(0.5).lineLimit(1)
                    Text(data.primaryCurrency).font(.system(size: 8)).foregroundStyle(.secondary)
                }
            }

        case .accessoryRectangular:
            let up = data.netWorthMonthChange >= 0
            HStack(spacing: 6) {
                Image(systemName: "chart.pie.fill").font(.caption2)
                VStack(alignment: .leading, spacing: 1) {
                    Text(data.str("netWorth")).font(.system(size: 9)).foregroundStyle(.secondary)
                    Text("\(data.formattedFull(data.netWorth)) \(symbol)")
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .lineLimit(1).minimumScaleFactor(0.6)
                    HStack(spacing: 3) {
                        Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 8, weight: .bold))
                        Text("\(data.formattedShort(data.netWorthMonthChange)) \(data.str("thisMonth"))")
                            .font(.system(size: 9, weight: .medium))
                    }
                }
                Spacer(minLength: 0)
            }

        default: // accessoryInline
            let up = data.netWorthMonthChange >= 0
            Text("\(Image(systemName: up ? "arrow.up.right" : "arrow.down.right")) \(data.formattedFull(data.netWorth)) \(symbol)")
        }
    }
}
