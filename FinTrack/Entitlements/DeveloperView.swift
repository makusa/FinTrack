//
//  DeveloperView.swift
//  FinTrack
//
//  ⚠️  DEBUG ONLY — not compiled in Release builds.
//  Allows quick switching between Free / Pro / Plaid tiers
//  without going through the App Store purchase flow.
//  Also provides instant notification firing for testing.
//

#if DEBUG

import SwiftUI
import UserNotifications

struct DeveloperView: View {
    @Environment(LanguageManager.self) private var lang
    @Environment(EntitlementManager.self) private var entitlements

    // Tier switching
    @State private var showConfirm   = false
    @State private var pendingTier:  FinTrackTier? = nil

    // Notification testing
    @State private var pendingNotifs: [UNNotificationRequest] = []
    @State private var showFireConfirm = false
    @State private var firedCount: Int = 0
    @State private var showFiredBanner = false
    @State private var isFiring = false

    // MARK: - Tier definitions

    private struct TierOption {
        let tier:       FinTrackTier
        let name:       String
        let subtitle:   String
        let icon:       String
        let color:      Color
        let features:   [String]
    }

    private let options: [TierOption] = [
        TierOption(
            tier:     .free,
            name:     "Courant",
            subtitle: "Version gratuite",
            icon:     "person.circle.fill",
            color:    .gray,
            features: ["Comptes manuels illimités", "Transactions manuelles", "Dashboard basique"]
        ),
        TierOption(
            tier:     .pro,
            name:     "Épargne",
            subtitle: "Achat unique",
            icon:     "star.circle.fill",
            color:    .orange,
            features: ["Tout Courant +", "Budgets, prêts, marges", "Analytiques & graphiques",
                       "Récurrences & virements", "Taux de change", "Dashboard custom", "Export CSV"]
        ),
        TierOption(
            tier:     .plaid,
            name:     "Placement",
            subtitle: "Abonnement mensuel",
            icon:     "building.columns.circle.fill",
            color:    .teal,
            features: ["Tout Épargne +", "Connexion bancaire Plaid", "Sync automatique des transactions"]
        ),
    ]

    // MARK: - Body

    var body: some View {
        List {
            warningBanner
            tierStatusSection
            tierSwitcherSection
            quickActionsSection
            notificationSection
            if !pendingNotifs.isEmpty { pendingListSection }
        }
        .navigationTitle("Développeur 🛠")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { Task { await loadPendingNotifs() } }
        // Tier confirm dialog
        .confirmationDialog(
            "Changer vers \(pendingTier.map { tierName($0) } ?? "") ?",
            isPresented: $showConfirm,
            titleVisibility: .visible
        ) {
            if let tier = pendingTier {
                Button("Confirmer") { apply(tier) }
                Button("Annuler", role: .cancel) { pendingTier = nil }
            }
        } message: {
            Text("L'app simulera ce tier jusqu'au redémarrage ou reset.")
        }
        // Fire confirm dialog
        .confirmationDialog(
            "Déclencher \(pendingNotifs.count) notification\(pendingNotifs.count > 1 ? "s" : "") ?",
            isPresented: $showFireConfirm,
            titleVisibility: .visible
        ) {
            Button("Déclencher maintenant") {
                Task { await fireAllNotificationsNow() }
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Chaque notification sera envoyée avec 2 s d'intervalle. Les notifications réelles restent planifiées.")
        }
        // Fired confirmation banner (overlay)
        .overlay(alignment: .top) {
            if showFiredBanner {
                firedBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 8)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showFiredBanner)
    }

    // MARK: - Sections

    private var warningBanner: some View {
        Section {
            HStack(spacing: 10) {
                Image(systemName: "hammer.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mode développeur")
                        .font(.callout.weight(.semibold))
                    Text("Visible uniquement en build DEBUG. Non compilé en Release.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(Color.orange.opacity(0.08))
    }

    private var tierStatusSection: some View {
        Section("Tier actuel") {
            HStack(spacing: 12) {
                Image(systemName: currentOption.icon)
                    .font(.title2)
                    .foregroundStyle(currentOption.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(currentOption.name)
                        .font(.body.weight(.semibold))
                    Text(currentOption.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                activeBadge
            }
            .padding(.vertical, 4)
        }
    }

    private var tierSwitcherSection: some View {
        Section("Changer de tier") {
            ForEach(options, id: \.name) { option in
                tierRow(option)
            }
        }
    }

    private var quickActionsSection: some View {
        Section("Actions rapides") {
            Button {
                UIPasteboard.general.string = """
                Tier: \(currentOption.name)
                hasPro: \(entitlements.hasPro)
                hasPlaid: \(entitlements.hasPlaid)
                """
            } label: {
                Label("Copier l'état actuel", systemImage: "doc.on.doc")
            }

            Button(role: .destructive) {
                entitlements.simulateFree()
            } label: {
                Label("Réinitialiser → Courant", systemImage: "arrow.counterclockwise")
            }
        }
    }

    private var notificationSection: some View {
        Section {
            // Count row
            HStack {
                Image(systemName: "bell")
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                Text("Planifiées")
                Spacer()
                Text("\(pendingNotifs.count)")
                    .monospacedDigit()
                    .foregroundStyle(pendingNotifs.isEmpty
                                     ? AnyShapeStyle(.secondary)
                                     : AnyShapeStyle(Color.orange))
                    .fontWeight(pendingNotifs.isEmpty ? .regular : .semibold)
            }

            // Fire all button
            Button {
                if pendingNotifs.isEmpty {
                    Task { await loadPendingNotifs() }
                } else {
                    showFireConfirm = true
                }
            } label: {
                HStack {
                    if isFiring {
                        ProgressView().scaleEffect(0.8).padding(.trailing, 4)
                    } else {
                        Image(systemName: "bell.badge.fill")
                            .foregroundStyle(pendingNotifs.isEmpty ? .secondary : .red)
                            .frame(width: 24)
                    }
                    Text(pendingNotifs.isEmpty
                         ? "Aucune notification planifiée"
                         : "Déclencher toutes immédiatement")
                        .foregroundStyle(pendingNotifs.isEmpty ? .secondary : .primary)
                }
            }
            .disabled(pendingNotifs.isEmpty || isFiring)

            // Refresh
            Button {
                Task { await loadPendingNotifs() }
            } label: {
                Label("Actualiser la liste", systemImage: "arrow.clockwise")
            }
        } header: {
            Text("Notifications")
        } footer: {
            Text("Les notifications de test sont envoyées avec 2 s d'intervalle et n'effacent pas les notifications réelles.")
        }
    }

    private var pendingListSection: some View {
        Section("Planifiées (\(pendingNotifs.count))") {
            ForEach(pendingNotifs.prefix(15), id: \.identifier) { req in
                VStack(alignment: .leading, spacing: 3) {
                    Text(req.content.title)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    if !req.content.body.isEmpty {
                        Text(req.content.body)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    if let trigger = req.trigger as? UNCalendarNotificationTrigger,
                       let next = trigger.nextTriggerDate() {
                        Label(next.formatted(date: .abbreviated, time: .shortened),
                              systemImage: "clock")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.vertical, 2)
            }
            if pendingNotifs.count > 15 {
                Text("… et \(pendingNotifs.count - 15) autres")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var firedBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("\(firedCount) notification\(firedCount > 1 ? "s" : "") envoyée\(firedCount > 1 ? "s" : "") · 2 s d'intervalle")
                .font(.callout.weight(.medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .shadow(radius: 4, y: 2)
    }

    // MARK: - Notification logic

    private func loadPendingNotifs() async {
        let center = UNUserNotificationCenter.current()
        let all = await center.pendingNotificationRequests()
        // Exclude previous test notifications
        let real = all.filter { !$0.identifier.hasSuffix(".devtest") }
        await MainActor.run { pendingNotifs = real }
    }

    private func fireAllNotificationsNow() async {
        guard !pendingNotifs.isEmpty else { return }

        await MainActor.run { isFiring = true }
        let center = UNUserNotificationCenter.current()

        // Remove stale devtest notifications from previous runs
        let existing = await center.pendingNotificationRequests()
        let staleIds = existing.filter { $0.identifier.hasSuffix(".devtest") }.map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: staleIds)

        // Re-schedule each notification with a short staggered delay
        var count = 0
        let batch = Array(pendingNotifs.prefix(15))   // cap at 15 to avoid flooding
        for (i, req) in batch.enumerated() {
            let delay = Double(i + 1) * 2.0           // 2 s, 4 s, 6 s …
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
            let testReq = UNNotificationRequest(
                identifier: req.identifier + ".devtest",
                content: req.content,
                trigger: trigger
            )
            try? await center.add(testReq)
            count += 1
        }

        await MainActor.run {
            isFiring = false
            firedCount = count
            showFiredBanner = true
        }

        // Auto-dismiss the confirmation banner after 3 s
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        await MainActor.run { showFiredBanner = false }

        // Refresh pending count
        await loadPendingNotifs()
    }

    // MARK: - Tier row

    private func tierRow(_ option: TierOption) -> some View {
        let isCurrent = entitlements.tier == option.tier

        return Button {
            if !isCurrent {
                pendingTier = option.tier
                showConfirm = true
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: option.icon)
                    .font(.title3)
                    .foregroundStyle(isCurrent ? .white : option.color)
                    .frame(width: 40, height: 40)
                    .background(
                        isCurrent ? option.color : option.color.opacity(0.12),
                        in: Circle()
                    )

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(option.name)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.primary)
                        if isCurrent {
                            Text("ACTIF")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(option.color.opacity(0.15), in: Capsule())
                                .foregroundStyle(option.color)
                        }
                    }
                    Text(option.features.prefix(2).joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if !isCurrent {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(isCurrent ? option.color.opacity(0.06) : Color.clear)
    }

    // MARK: - Helpers

    private var currentOption: TierOption {
        options.first { $0.tier == entitlements.tier } ?? options[0]
    }

    private var activeBadge: some View {
        Text("● ACTIF")
            .font(.caption2.weight(.bold))
            .foregroundStyle(currentOption.color)
    }

    private func tierName(_ tier: FinTrackTier) -> String {
        options.first { $0.tier == tier }?.name ?? ""
    }

    private func apply(_ tier: FinTrackTier) {
        Task { @MainActor in
            switch tier {
            case .free:  entitlements.simulateFree()
            case .pro:   entitlements.simulatePro()
            case .plaid: entitlements.simulatePlaid()
            }
        }
        pendingTier = nil
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        DeveloperView()
            .environment(LanguageManager.shared)
    }
}

#endif
