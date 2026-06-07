//
//  DashboardLibraryView.swift
//  FinTrack
//
//  Full-screen editor for the dashboard layout.
//  Active widgets can be reordered by drag. Any widget can be moved
//  to the "library" (disabled) and re-enabled from there.
//

import SwiftUI

struct DashboardLibraryView: View {
    @Environment(\.dismiss)      private var dismiss
    @Environment(LanguageManager.self) private var lang

    @State private var config = DashboardConfigManager.shared
    @State private var isEditMode: EditMode = .active

    var body: some View {
        NavigationStack {
            List {
                // MARK: Active widgets
                Section {
                    ForEach(config.enabled) { widget in
                        widgetRow(widget, active: true)
                    }
                    .onMove { source, dest in
                        config.move(from: source, to: dest)
                    }
                    .onDelete { offsets in
                        for idx in offsets {
                            let widget = config.enabled[idx]
                            config.disable(widget)
                        }
                    }
                } header: {
                    Text(lang["library.active"])
                } footer: {
                    Text(lang["library.active.footer"])
                }

                // MARK: Library (disabled)
                if !config.disabled.isEmpty {
                    Section {
                        ForEach(config.disabled) { widget in
                            widgetRow(widget, active: false)
                        }
                    } header: {
                        Text(lang["library.available"])
                    } footer: {
                        Text(lang["library.available.footer"])
                    }
                }

                // MARK: Reset
                Section {
                    Button(role: .destructive) {
                        withAnimation { config.resetToDefaults() }
                    } label: {
                        Label(lang["library.reset"], systemImage: "arrow.counterclockwise")
                    }
                }
            }
            .environment(\.editMode, $isEditMode)
            .navigationTitle(lang["library.title"])
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(lang["action.close"]) { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func widgetRow(_ widget: DashboardWidgetID, active: Bool) -> some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(active ? Color.accentColor.opacity(0.12) : Color(.systemGray5))
                    .frame(width: 36, height: 36)
                Image(systemName: widget.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(active ? Color.accentColor : Color.secondary)
            }

            // Labels
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(widget.title)
                        .font(.body.weight(.medium))
                    if widget.isPinned {
                        Text(lang["library.pinned"])
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.12),
                                        in: Capsule())
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Text(widget.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Add/remove button (disabled section only, active uses swipe)
            if !active {
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        config.enable(widget)
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
        // Disable delete/move for pinned
        .deleteDisabled(widget.isPinned)
        .moveDisabled(widget.isPinned)
    }
}
