//  FinTrackWidgetEntry.swift — Timeline entry and providers shared by the widgets
import WidgetKit
import Foundation
import AppIntents

struct FinTrackEntry: TimelineEntry {
    let date: Date
    let data: FinTrackWidgetData
    var content: WidgetContentType = .netWorth
}

// Static provider — used by the Accessory and Room widgets (no configuration).
struct FinTrackProvider: TimelineProvider {
    func placeholder(in context: Context) -> FinTrackEntry {
        FinTrackEntry(date: .now, data: .placeholder)
    }
    func getSnapshot(in context: Context, completion: @escaping (FinTrackEntry) -> Void) {
        completion(FinTrackEntry(date: .now, data: .load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<FinTrackEntry>) -> Void) {
        let entry    = FinTrackEntry(date: .now, data: .load())
        let nextDate = Calendar.current.date(byAdding: .hour, value: 1, to: .now)!
        completion(Timeline(entries: [entry], policy: .after(nextDate)))
    }
}

// Configurable provider — used by the Balance widget (content selector intent).
struct FinTrackConfigProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> FinTrackEntry {
        FinTrackEntry(date: .now, data: .placeholder, content: .netWorth)
    }
    func snapshot(for configuration: SelectContentIntent, in context: Context) async -> FinTrackEntry {
        FinTrackEntry(date: .now, data: .load(), content: configuration.content)
    }
    func timeline(for configuration: SelectContentIntent, in context: Context) async -> Timeline<FinTrackEntry> {
        let entry    = FinTrackEntry(date: .now, data: .load(), content: configuration.content)
        let nextDate = Calendar.current.date(byAdding: .hour, value: 1, to: .now)!
        return Timeline(entries: [entry], policy: .after(nextDate))
    }
}
