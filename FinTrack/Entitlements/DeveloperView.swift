//
//  DeveloperView.swift
//  FinTrack
//
//  ⚠️  DEBUG ONLY — not compiled in Release builds.
//  Allows quick switching between Free / Pro / Plaid tiers
//  without going through the App Store purchase flow.
//

#if DEBUG

import SwiftUI

struct DeveloperView: View {
    @Environment(LanguageManager.self) private var lang
    @Environment(EntitlementManager.self) private var entitlements
    @State private var showConfirm   = false
    @State private var pendingTier:  FinTrackTier? = nil

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
            // Warning banner
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

            // Current tier status
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

            // Tier switcher
            Section("Changer de tier") {
                ForEach(options, id: \.name) { option in
                    tierRow(option)
                }
            }

            // Quick actions
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
        .navigationTitle("Développeur 🛠")
        .navigationBarTitleDisplayMode(.inline)
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
                // Icon
                Image(systemName: option.icon)
                    .font(.title3)
                    .foregroundStyle(isCurrent ? .white : option.color)
                    .frame(width: 40, height: 40)
                    .background(
                        isCurrent ? option.color : option.color.opacity(0.12),
                        in: Circle()
                    )

                // Info
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
