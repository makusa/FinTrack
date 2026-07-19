//  FinTrackRoomWidget.swift — Registered-account contribution room (CELI / CELIAPP / REER)
//  Same "Focus" look: side accent (red if any over-contribution, else green),
//  rounded amounts, usage bars. The differentiator on the Home & Lock screen.
import WidgetKit
import SwiftUI

struct FinTrackRoomWidget: Widget {
    let kind = "fintrack.room"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FinTrackProvider()) { entry in
            FinTrackRoomView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Contribution Room")
        .description("Available contribution room (TFSA, FHSA, RRSP).")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

struct FinTrackRoomView: View {
    let entry: FinTrackEntry
    @Environment(\.widgetFamily) private var family
    private var data: FinTrackWidgetData { entry.data }
    private var rooms: [FinTrackWidgetData.RegisteredRoomEntry] { data.registeredRooms }
    private var accentColor: Color { rooms.contains(where: { $0.isOver }) ? .red : .green }

    var body: some View {
        switch family {
        case .systemSmall:       smallView
        case .accessoryCircular: circularView
        default:                 rectangularView
        }
    }

    // Home Small: side accent + up to 3 types with available room + usage bar.
    private var smallView: some View {
        HStack(spacing: 0) {
            SideAccent(color: accentColor)
            VStack(alignment: .leading, spacing: 6) {
                WidgetCaption(text: data.str("room"))
                if rooms.isEmpty {
                    Spacer()
                    Text(data.str("noData")).font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                } else {
                    ForEach(rooms.prefix(3)) { room in
                        VStack(spacing: 2) {
                            HStack {
                                Text(room.shortName).font(.caption2.weight(.semibold))
                                Spacer()
                                Text(data.formattedSigned(room.available))
                                    .font(.system(.caption, design: .rounded).weight(.bold))
                                    .foregroundStyle(room.isOver ? .red : .green)
                            }
                            ProgressView(value: room.usedFraction).tint(room.isOver ? .red : .accentColor)
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

    // Lock Circular: gauge of the first (usually primary) registered type.
    @ViewBuilder
    private var circularView: some View {
        if let room = rooms.first {
            Gauge(value: room.usedFraction) {
                Text(room.shortName)
            } currentValueLabel: {
                Text(data.formattedShort(room.available)).minimumScaleFactor(0.5)
            }
            .gaugeStyle(.accessoryCircular)
            .tint(room.isOver ? .red : .green)
        } else {
            Image(systemName: "leaf.fill")
        }
    }

    // Lock Rectangular: up to 2 types with available room.
    @ViewBuilder
    private var rectangularView: some View {
        if rooms.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "leaf.fill").font(.caption2)
                Text(data.str("noData")).font(.caption2)
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Label(data.str("room"), systemImage: "leaf.fill")
                    .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                ForEach(rooms.prefix(2)) { room in
                    HStack(spacing: 4) {
                        Text(room.shortName).font(.caption2.weight(.semibold))
                        Spacer()
                        Text("\(data.formattedSigned(room.available)) \(data.str("available"))")
                            .font(.system(.caption2, design: .rounded).weight(.medium))
                            .foregroundStyle(room.isOver ? .red : .primary)
                    }
                }
            }
        }
    }
}
