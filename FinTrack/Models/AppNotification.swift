//  AppNotification.swift — In-app notification center (bell)
//
//  Lightweight, persisted in-app notifications surfaced via the bell in the top bar.
//  Today they carry on-device automatic detections (recurring payments); the same
//  channel will later carry anomalies, transfer hints, due-date reminders, etc.
import Foundation
import SwiftData
import SwiftUI

enum AppNotificationKind: String, Codable {
    case recurrenceSuggestion
    case info

    var iconSystemName: String {
        switch self {
        case .recurrenceSuggestion: return "repeat.circle.fill"
        case .info:                 return "bell.fill"
        }
    }

    var tint: Color {
        switch self {
        case .recurrenceSuggestion: return .purple
        case .info:                 return .blue
        }
    }
}

@Model
final class AppNotification {
    var uuid: String = UUID().uuidString
    var kindRaw: String = AppNotificationKind.info.rawValue
    var title: String = ""
    var message: String = ""
    var createdAt: Date = Date.now
    var isRead: Bool = false
    /// Stable key to avoid re-posting the same event (e.g. a recurrence suggestion id).
    var dedupKey: String?

    var kind: AppNotificationKind { AppNotificationKind(rawValue: kindRaw) ?? .info }

    init(kind: AppNotificationKind, title: String, message: String, dedupKey: String? = nil) {
        self.uuid = UUID().uuidString
        self.kindRaw = kind.rawValue
        self.title = title
        self.message = message
        self.createdAt = .now
        self.isRead = false
        self.dedupKey = dedupKey
    }
}

/// Creates and manages in-app notifications. Intent-neutral — callers gate on tier.
enum AppNotificationCenter {

    /// Post a notification unless one with the same `dedupKey` already exists.
    /// Returns true if a new notification was inserted.
    @discardableResult
    static func post(kind: AppNotificationKind, title: String, message: String,
                     dedupKey: String? = nil, in context: ModelContext) -> Bool {
        if let key = dedupKey {
            var descriptor = FetchDescriptor<AppNotification>(predicate: #Predicate { $0.dedupKey == key })
            descriptor.fetchLimit = 1
            if let existing = try? context.fetch(descriptor), !existing.isEmpty { return false }
        }
        context.insert(AppNotification(kind: kind, title: title, message: message, dedupKey: dedupKey))
        return true
    }

    static func markAllRead(in context: ModelContext) {
        let descriptor = FetchDescriptor<AppNotification>(predicate: #Predicate { !$0.isRead })
        guard let unread = try? context.fetch(descriptor), !unread.isEmpty else { return }
        for n in unread { n.isRead = true }
        try? context.save()
    }

    static func clearAll(in context: ModelContext) {
        guard let all = try? context.fetch(FetchDescriptor<AppNotification>()) else { return }
        for n in all { context.delete(n) }
        try? context.save()
    }
}

extension AppNotificationCenter {
    /// Detect recurrences now and post notifications for any newly found ones.
    /// Deduplicated, so calling this repeatedly (launch, after saving a transaction)
    /// is safe and won't repeat notifications. Caller gates on tier.
    static func refreshRecurrenceNotifications(in context: ModelContext) {
        let dismissed = Set(UserDefaults.standard.stringArray(forKey: "recurring.dismissedSuggestions") ?? [])
        let suggestions = RecurrenceDetector.detect(in: context, dismissed: dismissed)
        postRecurrenceSuggestions(suggestions, in: context)
    }

    /// Post one notification per recurrence suggestion not already surfaced
    /// (deduplicated by the suggestion's stable id). Saves once if anything changed.
    static func postRecurrenceSuggestions(_ suggestions: [RecurrenceDetector.Suggestion],
                                          in context: ModelContext) {
        let lang = LanguageManager.shared
        var posted = false
        for s in suggestions {
            let amount = s.amount.formatted(asCurrency: s.currency)
            let message = "\(s.payee) · \(amount) · \(s.frequency.label)"
            if post(kind: .recurrenceSuggestion,
                    title: lang["notif.recurrence.title"],
                    message: message,
                    dedupKey: "recurrence:\(s.id)",
                    in: context) {
                posted = true
            }
        }
        if posted { try? context.save() }
    }
}
