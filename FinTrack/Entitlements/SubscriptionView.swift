//
//  SubscriptionView.swift
//  FinTrack
//
//  Full subscription management screen:
//    - Shows current tier
//    - Lets user upgrade or manage subscription
//

import SwiftUI
import StoreKit

struct SubscriptionView: View {
    @Environment(LanguageManager.self) private var lang
    @State private var entitlements = EntitlementManager.shared
    @State private var showError = false

    var body: some View {
        List {
            // MARK: Current tier banner
            Section {
                tierBanner
            }
            .listRowBackground(Color.clear)
            .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))

            // MARK: Plans
            if !entitlements.hasPro {
                Section(lang["entitlement.plans"]) {
                    planRow(product: .pro)
                }
            }

            if !entitlements.hasPlaid {
                Section {
                    planRow(product: .plaidMonthly)
                } footer: {
                    Text(lang["entitlement.plaid.footer"])
                }
            }

            // MARK: Manage
            Section(lang["entitlement.manage"]) {
                Button(lang["entitlement.restore"]) {
                    Task { await entitlements.restore() }
                }
                .disabled(entitlements.isLoading)

                if entitlements.hasPlaid {
                    Link(lang["entitlement.manage.subscription"],
                         destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
                }
            }

            // MARK: What's included
            Section(lang["entitlement.whatsincluded"]) {
                tierComparisonTable
            }
        }
        .navigationTitle(lang["entitlement.title"])
        .navigationBarTitleDisplayMode(.inline)
        .task { await entitlements.loadProducts() }
        .alert(lang["entitlement.error"], isPresented: $showError) {
            Button(lang["action.ok"], role: .cancel) {}
        } message: {
            Text(entitlements.purchaseError ?? "")
        }
        .onChange(of: entitlements.purchaseError) { _, err in
            if err != nil { showError = true }
        }
    }

    // MARK: - Tier banner

    private var tierBanner: some View {
        HStack(spacing: 14) {
            Image(systemName: tierIcon)
                .font(.system(size: 28))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(tierGradient, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(tierName)
                    .font(.title3.weight(.bold))
                Text(tierSubtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private var tierIcon: String {
        switch entitlements.tier {
        case .free:  return "person.circle"
        case .pro:   return "star.fill"
        case .plaid: return "building.columns.badge.plus"
        }
    }

    private var tierName: String {
        switch entitlements.tier {
        case .free:  return lang["entitlement.free.name"]
        case .pro:   return lang["entitlement.pro.name"]
        case .plaid: return lang["entitlement.plaid.name"] + " + Pro"
        }
    }

    private var tierSubtitle: String {
        switch entitlements.tier {
        case .free:  return lang["entitlement.free.subtitle"]
        case .pro:   return lang["entitlement.pro.subtitle"]
        case .plaid: return lang["entitlement.plaid.subtitle"]
        }
    }

    private var tierGradient: LinearGradient {
        switch entitlements.tier {
        case .free:
            return LinearGradient(colors: [.gray, .gray.opacity(0.7)], startPoint: .top, endPoint: .bottom)
        case .pro:
            return LinearGradient(colors: [.orange, .yellow], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .plaid:
            return LinearGradient(colors: [.teal, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    // MARK: - Plan row

    private func planRow(product: FinTrackProduct) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: product.icon)
                    .foregroundStyle(product == .pro ? .orange : .teal)
                Text(product.displayName)
                    .font(.body.weight(.semibold))
                Spacer()
                if let p = entitlements.product(for: product) {
                    Text(p.displayPrice)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Text(product == .pro
                 ? lang["entitlement.pro.description"]
                 : lang["entitlement.plaid.description"])
                .font(.callout)
                .foregroundStyle(.secondary)

            Button {
                Task { _ = await entitlements.purchase(product) }
            } label: {
                Group {
                    if entitlements.isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Text(product == .pro
                             ? lang["entitlement.pro.cta"]
                             : lang["entitlement.plaid.cta"])
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .font(.body.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(product == .pro ? .orange : .teal)
            .disabled(entitlements.isLoading)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Comparison table

    private struct FeatureRow {
        let name: String
        let free: Bool
        let pro: Bool
        let plaid: Bool
    }

    private var features: [FeatureRow] {
        [
            FeatureRow(name: lang["entitlement.table.accounts3"],    free: true,  pro: true,  plaid: true),
            FeatureRow(name: lang["entitlement.table.transactions"],  free: true,  pro: true,  plaid: true),
            FeatureRow(name: lang["entitlement.table.budgets"],       free: false, pro: true,  plaid: true),
            FeatureRow(name: lang["entitlement.table.loans"],         free: false, pro: true,  plaid: true),
            FeatureRow(name: lang["entitlement.table.analytics"],     free: false, pro: true,  plaid: true),
            FeatureRow(name: lang["entitlement.table.recurring"],     free: false, pro: true,  plaid: true),
            FeatureRow(name: lang["entitlement.table.transfers"],     free: false, pro: true,  plaid: true),
            FeatureRow(name: lang["entitlement.table.fx"],            free: false, pro: true,  plaid: true),
            FeatureRow(name: lang["entitlement.table.dashboard"],     free: false, pro: true,  plaid: true),
            FeatureRow(name: lang["entitlement.table.export"],        free: false, pro: true,  plaid: true),
            FeatureRow(name: lang["entitlement.table.plaid"],         free: false, pro: false, plaid: true),
        ]
    }

    private var tierComparisonTable: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(lang["entitlement.table.feature"])
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Free").font(.caption.weight(.semibold)).foregroundStyle(.gray).frame(width: 44)
                Text("Pro").font(.caption.weight(.semibold)).foregroundStyle(.orange).frame(width: 44)
                Text("Plaid").font(.caption.weight(.semibold)).foregroundStyle(.teal).frame(width: 44)
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 8)

            Divider()

            ForEach(Array(features.enumerated()), id: \.offset) { _, row in
                HStack {
                    Text(row.name)
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    checkmark(row.free, color: .gray).frame(width: 44)
                    checkmark(row.pro,  color: .orange).frame(width: 44)
                    checkmark(row.plaid, color: .teal).frame(width: 44)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 2)
                Divider()
            }
        }
    }

    private func checkmark(_ value: Bool, color: Color) -> some View {
        Image(systemName: value ? "checkmark.circle.fill" : "xmark.circle")
            .foregroundStyle(value ? color : Color(.tertiaryLabel))
            .font(.system(size: 16))
    }
}
