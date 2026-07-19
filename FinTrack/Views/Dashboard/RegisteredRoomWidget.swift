//
//  RegisteredRoomWidget.swift
//  FinTrack
//
//  Dashboard widget: contribution room per registered-account type
//  (CELI / CELIAPP / REER). Shows the available room and a usage bar toward the
//  relevant ceiling. Reads ALL accounts (archived included) because room is
//  historical (per person per type), plus the per-type anchor plan. Free-tier
//  feature, like the registered-accounts hub it links to.
//
//  Denominator of the usage bar differs by type (see roomRow): CELIAPP has a
//  $40,000 lifetime cap, so the bar tracks contributed / cap; CELI/REER have no
//  lifetime cap, so it tracks contributed / (contributed + available) — i.e. the
//  room made available since the anchor.
//

import SwiftUI
import SwiftData

struct RegisteredRoomWidget: View {
    @Environment(LanguageManager.self) private var lang

    @Query private var allPlans: [RegisteredRoomPlan]
    @Query private var allAccounts: [Account]   // tous, archivés inclus (le droit est historique)

    private let types: [RegisteredType] = [.celi, .celiapp, .reer]

    /// Types à afficher : ceux avec un compte enregistré OU un plan d'ancre.
    private var visibleTypes: [RegisteredType] {
        types.filter { type in
            allAccounts.contains { $0.registeredProfile?.registeredType == type }
                || allPlans.contains { $0.registeredType == type }
        }
    }

    var body: some View {
        if !visibleTypes.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(lang["reg.hub.title"])
                        .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                    Spacer()
                    NavigationLink(lang["action.seeAll"]) { RegisteredAccountsView() }
                        .font(.caption)
                }
                .padding(.horizontal)
                card
            }
        }
    }

    private var card: some View {
        VStack(spacing: 0) {
            ForEach(Array(visibleTypes.enumerated()), id: \.element) { idx, type in
                NavigationLink {
                    RegisteredAccountsView()
                } label: {
                    row(for: type)
                }
                .buttonStyle(.plain)
                if idx < visibleTypes.count - 1 {
                    Divider().padding(.vertical, 10)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    @ViewBuilder
    private func row(for type: RegisteredType) -> some View {
        let plan = allPlans.first { $0.registeredType == type }
        if let plan,
           let result = RegisteredRoomService.availableRoom(type: type, plan: plan, accounts: allAccounts) {
            roomRow(type, result)
        } else {
            // Compte enregistré présent mais aucune ancre configurée → inviter.
            HStack(spacing: 10) {
                iconBadge(type)
                Text(type.shortName).font(.subheadline.weight(.semibold))
                Spacer()
                Text(lang["reg.room.configure"])
                    .font(.caption).foregroundStyle(.blue).lineLimit(1)
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    private func roomRow(_ type: RegisteredType, _ result: RoomResult) -> some View {
        let contributed = result.lifetimeContributed
        let available   = result.availableRoom
        // Plafond à vie si défini (CELIAPP 40 000), sinon droit total depuis
        // l'ancre = cotisé + disponible (CELI/REER n'ont pas de plafond à vie).
        let denom = type.lifetimeCap ?? (contributed + max(available, 0))
        let fraction: Double = {
            let d = (denom as NSDecimalNumber).doubleValue
            guard d > 0 else { return result.isOverContributed ? 1 : 0 }
            let c = (contributed as NSDecimalNumber).doubleValue
            return min(max(c / d, 0), 1)
        }()

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                iconBadge(type)
                Text(type.shortName).font(.subheadline.weight(.semibold))
                Spacer()
                Text(available.formatted(asCurrency: "CAD"))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(result.isOverContributed ? .red : .green)
            }
            ProgressView(value: fraction)
                .tint(result.isOverContributed ? .red : .accentColor)
            if result.isOverContributed {
                Label("\(lang["reg.room.over"]) : \(result.excess.formatted(asCurrency: "CAD"))",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2).foregroundStyle(.red)
            } else {
                Text(captionText(type: type, contributed: contributed, cap: denom))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    /// « Droit disponible · 12 000 $ cotisés » (+ « / 40 000 $ à vie » pour le CELIAPP).
    private func captionText(type: RegisteredType, contributed: Decimal, cap: Decimal) -> String {
        var s = "\(lang["reg.room.available"]) · \(contributed.formatted(asCurrency: "CAD")) \(lang["widget.registered.contributed"])"
        if type.lifetimeCap != nil {
            s += " / \(cap.formatted(asCurrency: "CAD")) \(lang["widget.registered.lifetime"])"
        }
        return s
    }

    private func iconBadge(_ type: RegisteredType) -> some View {
        Image(systemName: iconName(type))
            .font(.caption)
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(badgeColor(type), in: RoundedRectangle(cornerRadius: 6))
    }

    private func iconName(_ type: RegisteredType) -> String {
        switch type {
        case .celi:    return "leaf.fill"
        case .celiapp: return "house.fill"
        case .reer:    return "chart.line.uptrend.xyaxis"
        }
    }

    private func badgeColor(_ type: RegisteredType) -> Color {
        switch type {
        case .celi:    return .green
        case .celiapp: return .orange
        case .reer:    return .blue
        }
    }
}
