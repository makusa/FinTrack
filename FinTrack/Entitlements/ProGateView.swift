//
//  ProGateView.swift
//  FinTrack
//
//  Shown when a Free user tries to access a Pro or Plaid feature.
//  Lists what's included in each tier and presents a purchase / subscribe CTA.
//

import SwiftUI
import StoreKit

// MARK: - Gated feature definitions

enum GatedFeature {
    // Pro features
    case budgets
    case loans
    case creditLines
    case savings
    case recurring
    case transfers
    case analytics
    case cashFlow
    case exchangeRates
    case dashboardCustom
    case csvExport
    case unlimitedAccounts
    case registered
    case fileImport

    // Bank sync feature (Flinks ou Plaid — même gate)
    case bankSync
    static var plaidSync: GatedFeature { .bankSync }  // rétrocompatibilité

    var title: String {
        let lang = LanguageManager.shared
        switch self {
        case .budgets:           return lang["budget.title"]
        case .loans:             return lang["loan.title"]
        case .creditLines:       return lang["cl.title"]
        case .savings:           return lang["savings.title"]
        case .recurring:         return lang["recurring.title"]
        case .transfers:         return lang["transfer.title"]
        case .analytics:         return lang["analytics.title"]
        case .cashFlow:          return lang["cashflow.title"]
        case .exchangeRates:     return lang["fx.title"]
        case .dashboardCustom:   return lang["library.title"]
        case .csvExport:         return lang["settings.export"]
        case .unlimitedAccounts: return lang["entitlement.unlimited.accounts"]
        case .registered:        return lang["reg.hub.title"]
        case .fileImport:        return lang["import.ofx.title"]
        case .bankSync:          return lang["flinks.title"]
        }
    }

    var icon: String {
        switch self {
        case .budgets:           return "chart.bar.doc.horizontal"
        case .loans:             return "banknote.fill"
        case .creditLines:       return "creditcard.fill"
        case .savings:           return "star.fill"
        case .recurring:         return "arrow.clockwise.circle.fill"
        case .transfers:         return "arrow.left.arrow.right.circle.fill"
        case .analytics:         return "chart.pie.fill"
        case .cashFlow:          return "arrow.left.arrow.right.circle"
        case .exchangeRates:     return "arrow.left.arrow.right.circle"
        case .dashboardCustom:   return "square.grid.2x2"
        case .csvExport:         return "square.and.arrow.up"
        case .unlimitedAccounts: return "building.columns.fill"
        case .registered:        return "leaf.fill"
        case .fileImport:        return "arrow.down.doc"
        case .bankSync:          return "building.columns"
        }
    }

    var requiredProduct: FinTrackProduct {
        switch self {
        case .bankSync: return .placement  // synchro bancaire live — abonnement (Placement) uniquement
        default:         return .epargne
        }
    }
}

// MARK: - ProGateView

struct ProGateView: View {
    @Environment(LanguageManager.self) private var lang
    @Environment(EntitlementManager.self) private var entitlements

    let feature: GatedFeature
    @State private var isPurchasing = false
    @State private var showError    = false

    private var isPlaidGate: Bool { feature.requiredProduct == .placement }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                // Hero
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(
                                colors: isPlaidGate
                                    ? [Color.teal, Color.blue]
                                    : [Color.orange, Color.yellow],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing))
                            .frame(width: 80, height: 80)
                        Image(systemName: feature.icon)
                            .font(.system(size: 34))
                            .foregroundStyle(.white)
                    }

                    Text(feature.title)
                        .font(.title2.weight(.bold))

                    Text(isPlaidGate
                         ? lang["entitlement.plaid.tagline"]
                         : lang["entitlement.pro.tagline"])
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .padding(.top, 32)

                // Feature list
                VStack(alignment: .leading, spacing: 0) {
                    if isPlaidGate {
                        plaidFeatureList
                    } else {
                        proFeatureList
                    }
                }
                .background(Color(.secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)

                // Purchase CTA
                purchaseCTA

                // Restore
                Button(lang["entitlement.restore"]) {
                    Task { await entitlements.restore() }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle(isPlaidGate
                         ? lang["entitlement.plaid.name"]
                         : lang["entitlement.pro.name"])
        .navigationBarTitleDisplayMode(.inline)
        .alert(lang["entitlement.error"], isPresented: $showError) {
            Button(lang["action.ok"], role: .cancel) {}
        } message: {
            Text(entitlements.purchaseError ?? "")
        }
        .onChange(of: entitlements.purchaseError) { _, err in
            if err != nil { showError = true }
        }
    }

    // MARK: - Pro feature list

    private static let proFeatures: [(String, String)] = [
        ("chart.bar.doc.horizontal", "Budgets par catégorie"),
        ("banknote.fill",            "Gestion des prêts"),
        ("creditcard.fill",          "Marges de crédit"),
        ("star.fill",                "Projets d'épargne"),
        ("leaf.fill",                "Comptes enregistrés CELI/REER"),
        ("arrow.clockwise",          "Transactions récurrentes"),
        ("arrow.left.arrow.right",   "Virements entre comptes"),
        ("chart.pie.fill",           "Analytiques & graphiques"),
        ("square.grid.2x2",          "Dashboard personnalisable"),
        ("arrow.left.arrow.right.circle", "Taux de change live"),
        ("square.and.arrow.up",      "Export CSV"),
        ("building.columns.fill",    "Comptes illimités"),
    ]

    private var proFeatureList: some View {
        VStack(spacing: 0) {
            ForEach(Array(Self.proFeatures.enumerated()), id: \.offset) { idx, feature in
                HStack(spacing: 12) {
                    Image(systemName: feature.0)
                        .foregroundStyle(.orange)
                        .frame(width: 24)
                    Text(feature.1)
                        .font(.callout)
                    Spacer()
                    Image(systemName: "checkmark")
                        .foregroundStyle(.green)
                        .font(.caption.weight(.bold))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                if idx < Self.proFeatures.count - 1 {
                    Divider().padding(.leading, 52)
                }
            }
        }
    }

    // MARK: - Plaid feature list

    private static let plaidFeatures: [(String, String)] = [
        ("arrow.clockwise.circle.fill", "Sync automatique des transactions"),
        ("building.columns", "Jusqu'à 10 connexions bancaires"),
        ("checkmark.shield.fill",       "Connexion sécurisée et chiffrée"),
        ("dollarsign.circle.fill",      "Toutes les banques canadiennes"),
    ]

    private var plaidFeatureList: some View {
        VStack(spacing: 0) {
            ForEach(Array(Self.plaidFeatures.enumerated()), id: \.offset) { idx, feat in
                HStack(spacing: 12) {
                    Image(systemName: feat.0)
                        .foregroundStyle(.teal)
                        .frame(width: 24)
                    Text(feat.1)
                        .font(.callout)
                    Spacer()
                    Image(systemName: "checkmark")
                        .foregroundStyle(.green)
                        .font(.caption.weight(.bold))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                if idx < Self.plaidFeatures.count - 1 {
                    Divider().padding(.leading, 52)
                }
            }
        }
    }

    // MARK: - CTA

    private var purchaseCTA: some View {
        VStack(spacing: 12) {
            Button {
                Task { await buy() }
            } label: {
                Group {
                    if entitlements.isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        VStack(spacing: 2) {
                            Text(isPlaidGate
                                 ? lang["entitlement.plaid.cta"]
                                 : lang["entitlement.pro.cta"])
                                .font(.body.weight(.semibold))
                            if let product = entitlements.product(for: feature.requiredProduct) {
                                Text(product.displayPrice + (isPlaidGate ? " / " + lang["budget.period.monthly.short"] : ""))
                                    .font(.caption)
                                    .opacity(0.85)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
            }
            .buttonStyle(.borderedProminent)
            .tint(isPlaidGate ? .teal : .orange)
            .disabled(entitlements.isLoading)
            .padding(.horizontal)
        }
    }

    private func buy() async {
        _ = await entitlements.purchase(feature.requiredProduct)
    }
}

// MARK: - Convenience modifier

/// Wraps a view with a Pro gate — shown if user doesn't have the required entitlement.
struct ProGated<Content: View>: View {
    @Environment(EntitlementManager.self) private var entitlements
    let feature: GatedFeature
    let content: Content

    init(feature: GatedFeature, @ViewBuilder content: () -> Content) {
        self.feature = feature
        self.content = content()
    }

    var body: some View {
        let hasAccess: Bool = {
            switch feature.requiredProduct {
            case .epargne:          return entitlements.hasPaidTier
            case .placement: return entitlements.hasPlacement
            }
        }()

        if hasAccess {
            content
        } else {
            ProGateView(feature: feature)
        }
    }
}
