//
//  NotificationSettingsView.swift
//  FinTrack
//

import SwiftUI
import UserNotifications
import SwiftData

struct NotificationSettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(LanguageManager.self) private var lang

    @State private var authStatus: UNAuthorizationStatus = .notDetermined
    @State private var pendingCount: Int = 0
    @State private var isRescheduling = false

    var body: some View {
        List {
            // MARK: Status
            Section(lang["notification.status"]) {
                HStack {
                    Image(systemName: statusIcon)
                        .foregroundStyle(statusColor)
                    Text(statusLabel)
                    Spacer()
                }

                if authStatus == .denied {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label(lang["notification.openSettings"], systemImage: "arrow.up.right.square")
                    }
                }
            }

            // MARK: Scheduled
            if authStatus == .authorized || authStatus == .provisional {
                Section(lang["notification.pending"]) {
                    LabeledContent(lang["notification.pending"]) {
                        Text("\(pendingCount)")
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        reschedule()
                    } label: {
                        HStack {
                            Label(lang["notification.reschedule"], systemImage: "arrow.clockwise")
                            if isRescheduling {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isRescheduling)

                    Button(role: .destructive) {
                        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
                        pendingCount = 0
                    } label: {
                        Label(lang["notification.cancelAll"], systemImage: "bell.slash")
                    }
                }
            }

            // MARK: How it works
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("• " + lang["tab.transactions"] + " " + lang["label.expense"])
                    Text("• " + lang["recurring.title"])
                    Text("• " + lang["loan.title"])
                    Text("• " + lang["cl.title"])
                    Text("• " + lang["prepayment.title"])
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
            } header: {
                Text(lang["notification.section"])
            }
        }
        .navigationTitle(lang["notification.manage"])
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadStatus() }
    }

    // MARK: - Helpers

    private var statusIcon: String {
        switch authStatus {
        case .authorized, .provisional: return "bell.fill"
        case .denied:                   return "bell.slash.fill"
        default:                        return "bell"
        }
    }

    private var statusColor: Color {
        switch authStatus {
        case .authorized, .provisional: return .green
        case .denied:                   return .red
        default:                        return .secondary
        }
    }

    private var statusLabel: String {
        switch authStatus {
        case .authorized, .provisional: return lang["notification.authorized"]
        case .denied:                   return lang["notification.denied"]
        default:                        return lang["notification.status"]
        }
    }

    @MainActor
    private func loadStatus() async {
        authStatus = await NotificationManager.shared.authorizationStatus()
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        pendingCount = pending.filter { $0.identifier.hasPrefix("fintrack.") }.count
    }

    private func reschedule() {
        isRescheduling = true
        let ctx = context
        Task {
            await NotificationManager.shared.scheduleAll(context: ctx)
            await loadStatus()
            isRescheduling = false
        }
    }
}
