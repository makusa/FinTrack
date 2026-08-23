//  NotificationsView.swift — In-app notification center list (bell)
//
//  Shows persisted in-app notifications (on-device automatic detections today).
//  Opening the list marks everything read, which clears the bell badge.
import SwiftUI
import SwiftData

struct NotificationsView: View {
    @Environment(\.modelContext) private var context
    @Environment(LanguageManager.self) private var lang
    @Environment(\.dismiss) private var dismiss

    /// Called when the user taps a recurrence notification. The presenter fires the
    /// deep link in its sheet onDismiss, so the tab switch happens after this sheet
    /// has fully closed.
    var onNavigateToRecurrences: () -> Void = {}

    @Query(sort: \AppNotification.createdAt, order: .reverse)
    private var notifications: [AppNotification]

    var body: some View {
        NavigationStack {
            Group {
                if notifications.isEmpty {
                    ContentUnavailableView(lang["notif.empty"],
                                           systemImage: "bell.slash",
                                           description: Text(lang["notif.empty.sub"]))
                } else {
                    List {
                        ForEach(notifications) { notif in
                            row(notif)
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle(lang["notif.title"])
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(lang["action.done"]) { dismiss() }
                }
                if !notifications.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(lang["notif.clearAll"], role: .destructive) {
                            AppNotificationCenter.clearAll(in: context)
                        }
                    }
                }
            }
            .onAppear { AppNotificationCenter.markAllRead(in: context) }
        }
    }

    @ViewBuilder
    private func row(_ notif: AppNotification) -> some View {
        if notif.kind == .recurrenceSuggestion {
            Button { navigateToRecurrences() } label: { rowContent(notif) }
                .buttonStyle(.plain)
        } else {
            rowContent(notif)
        }
    }

    private func rowContent(_ notif: AppNotification) -> some View {
        HStack(spacing: 12) {
            Image(systemName: notif.kind.iconSystemName)
                .foregroundStyle(notif.kind.tint)
                .font(.title3)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(notif.title).font(.callout.weight(.medium))
                Text(notif.message).font(.subheadline).foregroundStyle(.secondary)
                Text(notif.createdAt.formatted(.relative(presentation: .named)))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            if notif.kind == .recurrenceSuggestion {
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    /// Ask the presenter to route to the Recurring screen, then close this sheet.
    /// The presenter fires the deep link in onDismiss (after full dismissal) so the
    /// tab switch + navigation aren't swallowed by the closing sheet.
    private func navigateToRecurrences() {
        onNavigateToRecurrences()
        dismiss()
    }

    private func delete(at offsets: IndexSet) {
        for i in offsets { context.delete(notifications[i]) }
        try? context.save()
    }
}
