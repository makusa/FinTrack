//
//  CloudSyncSettingsView.swift
//  FinTrack
//

import SwiftUI
import CloudKit

struct CloudSyncSettingsView: View {
    @Environment(LanguageManager.self) private var lang
    @State private var accountStatus: CKAccountStatus = .couldNotDetermine
    @State private var isLoading = true

    var body: some View {
        List {
            // MARK: Status
            Section(lang["icloud.status"]) {
                HStack(spacing: 12) {
                    Image(systemName: statusIcon)
                        .font(.title2)
                        .foregroundStyle(statusColor)
                        .frame(width: 36)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(statusTitle)
                            .font(.body.weight(.medium))
                        Text(statusSubtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)

                if accountStatus == .noAccount || accountStatus == .restricted {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label(lang["icloud.openSettings"], systemImage: "arrow.up.right.square")
                    }
                }
            }

            // MARK: Container info
            if accountStatus == .available {
                Section(lang["icloud.container"]) {
                    LabeledContent("Bundle ID") {
                        Text("ca.regis.fintrack")
                            .foregroundStyle(.secondary)
                            .font(.caption.monospaced())
                    }
                    LabeledContent("Container") {
                        Text("iCloud.ca.regis.fintrack")
                            .foregroundStyle(.secondary)
                            .font(.caption.monospaced())
                    }
                }
            }

            // MARK: How sync works
            Section {
                Text(lang["icloud.sync.info"])
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } header: {
                Label("iCloud CloudKit", systemImage: "arrow.triangle.2.circlepath.icloud")
            }
        }
        .navigationTitle(lang["icloud.manage"])
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isLoading {
                ProgressView()
            }
        }
        .task { await checkStatus() }
    }

    // MARK: - Status helpers

    private var statusIcon: String {
        switch accountStatus {
        case .available:          return "checkmark.icloud.fill"
        case .noAccount:          return "icloud.slash"
        case .restricted:         return "lock.icloud"
        case .couldNotDetermine:  return "questionmark.circle"
        case .temporarilyUnavailable: return "exclamationmark.icloud"
        @unknown default:         return "questionmark.circle"
        }
    }

    private var statusColor: Color {
        switch accountStatus {
        case .available:   return .green
        case .noAccount:   return .secondary
        case .restricted:  return .orange
        default:           return .red
        }
    }

    private var statusTitle: String {
        switch accountStatus {
        case .available:              return lang["icloud.available"]
        case .noAccount:              return lang["icloud.noAccount"]
        case .restricted:             return lang["icloud.restricted"]
        case .temporarilyUnavailable: return lang["icloud.unavailable"]
        default:                      return lang["icloud.unavailable"]
        }
    }

    private var statusSubtitle: String {
        switch accountStatus {
        case .available:
            return "iCloud.ca.regis.fintrack"
        case .noAccount:
            return lang["icloud.openSettings"]
        default:
            return "CloudKit"
        }
    }

    @MainActor
    private func checkStatus() async {
        do {
            accountStatus = try await CKContainer(identifier: "iCloud.ca.regis.fintrack").accountStatus()
        } catch {
            accountStatus = .couldNotDetermine
        }
        isLoading = false
    }
}
