//  FinTrackWidgetEntry.swift — Timeline entry and provider shared by all widgets

import WidgetKit
import Foundation

struct FinTrackEntry: TimelineEntry {
    let date: Date
    let data: FinTrackWidgetData
}

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
