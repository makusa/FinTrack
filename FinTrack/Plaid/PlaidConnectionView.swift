//
//  PlaidConnectionView.swift
//  FinTrack
//
//  Full UI for connecting bank accounts via Plaid:
//    - ConnectedAccountsView  — list of connected items + sync button
//    - PlaidLinkView          — WebView launching Plaid Link
//    - AccountMappingView     — map Plaid accounts to FinTrack accounts
//

import SwiftUI
import SwiftData
import WebKit

// MARK: - ConnectedAccountsView

struct ConnectedAccountsView: View {
    @Environment(\.modelContext) private var context
    @Environment(LanguageManager.self) private var lang
    @State private var plaid = PlaidManager.shared
    @Environment(EntitlementManager.self) private var entitlements

    @Query(filter: #Predicate<Account> { !$0.isArchived }, sort: \Account.createdAt)
    private var fintrackAccounts: [Account]

    @State private var showPlaidLink      = false
    @State private var isSyncing          = false
    @State private var syncResults:       [PlaidSyncEngine.SyncResult] = []
    @State private var showSyncSummary    = false
    @State private var itemToMap:         PlaidConnectedItem? = nil
    @State private var itemToDisconnect:  PlaidConnectedItem? = nil
    @State private var errorMessage:      String? = nil

    var body: some View {
        NavigationStack {
            if !entitlements.hasPaidTier {
                ProGateView(feature: .bankSync)
            } else {
            List {
                // ── Status banner ──────────────────────────────────────────
                if let err = errorMessage {
                    Section {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.callout)
                    }
                    .listRowBackground(Color.orange.opacity(0.08))
                }

                // ── Connected items ────────────────────────────────────────
                if plaid.connectedItems.isEmpty {
                    Section {
                        emptyState
                    }
                } else {
                    ForEach(plaid.connectedItems) { item in
                        Section {
                            connectedItemRow(item)
                        }
                    }
                }

                // ── Add account button ─────────────────────────────────────
                if !plaid.connectedItems.isEmpty {
                    Section {
                        Button {
                            showPlaidLink = true
                        } label: {
                            Label(lang["plaid.connect.add"], systemImage: "plus")
                        }
                    }
                }

                // ── Sync summary ───────────────────────────────────────────
                if showSyncSummary {
                    Section(lang["plaid.sync.summary"]) {
                        ForEach(syncResults, id: \.itemId) { result in
                            let item = plaid.connectedItems.first { $0.id == result.itemId }
                            HStack {
                                Image(systemName: result.error == nil ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(result.error == nil ? .green : .red)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item?.institutionName ?? result.itemId)
                                        .font(.callout.weight(.medium))
                                    if let err = result.error {
                                        Text(err.localizedDescription)
                                            .font(.caption)
                                            .foregroundStyle(.red)
                                    } else {
                                        Text("+\(result.added) · ~\(result.modified) · -\(result.removed)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }

                // ── Info footer ────────────────────────────────────────────
                Section {
                    Label(lang["plaid.security.note"], systemImage: "lock.shield")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(lang["plaid.title"])
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !plaid.connectedItems.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Task { await syncAll() }
                        } label: {
                            if isSyncing {
                                ProgressView().scaleEffect(0.8)
                            } else {
                                Label(lang["plaid.sync.now"], systemImage: "arrow.clockwise")
                            }
                        }
                        .disabled(isSyncing)
                    }
                }
            }
            .sheet(isPresented: $showPlaidLink) {
                PlaidLinkView { publicToken, metadata in
                    Task { await handleLinkSuccess(publicToken: publicToken, metadata: metadata) }
                }
            }
            .sheet(item: $itemToMap) { item in
                AccountMappingView(item: item, fintrackAccounts: fintrackAccounts)
            }
            .confirmationDialog(
                lang["plaid.disconnect.prompt"],
                isPresented: Binding(
                    get: { itemToDisconnect != nil },
                    set: { if !$0 { itemToDisconnect = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button(lang["action.delete"], role: .destructive) {
                    if let item = itemToDisconnect {
                        Task { try? await plaid.disconnect(item: item) }
                    }
                    itemToDisconnect = nil
                }
                Button(lang["action.cancel"], role: .cancel) { itemToDisconnect = nil }
            } message: {
                Text(lang["plaid.disconnect.message"])
            }
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "building.columns.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text(lang["plaid.empty.title"])
                .font(.title3.weight(.semibold))
            Text(lang["plaid.empty.sub"])
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
            Button {
                showPlaidLink = true
            } label: {
                Label(lang["plaid.connect.cta"], systemImage: "plus")
                    .font(.body.weight(.semibold))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .listRowBackground(Color.clear)
    }

    // MARK: - Connected item row

    private func connectedItemRow(_ item: PlaidConnectedItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.institutionName)
                        .font(.body.weight(.semibold))
                    if let date = item.lastSyncDate {
                        Text(lang["plaid.last.sync"] + " " +
                             date.appFormattedRelative())
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(lang["plaid.never.synced"])
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                Spacer()
                Menu {
                    Button {
                        itemToMap = item
                    } label: {
                        Label(lang["plaid.map.accounts"], systemImage: "link")
                    }
                    Button(role: .destructive) {
                        itemToDisconnect = item
                    } label: {
                        Label(lang["plaid.disconnect"], systemImage: "xmark.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                }
            }

            // Account chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(item.accounts) { acc in
                        HStack(spacing: 4) {
                            Image(systemName: accountIcon(type: acc.type))
                                .font(.caption2)
                            Text(acc.name)
                                .font(.caption)
                            if let mask = acc.mask {
                                Text("•••\(mask)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            acc.fintrackAccountId != nil
                                ? Color.green.opacity(0.12)
                                : Color(.systemGray5),
                            in: Capsule()
                        )
                        .foregroundStyle(acc.fintrackAccountId != nil ? .green : .primary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Logic

    private func handleLinkSuccess(publicToken: String, metadata: PlaidLinkMetadata) async {
        do {
            let accounts = metadata.accounts.map {
                PlaidAccountMeta(id: $0.id,
                                  name: $0.name,
                                  officialName: $0.officialName,
                                  type: $0.type,
                                  subtype: $0.subtype,
                                  mask: $0.mask,
                                  currencyCode: nil,
                                  fintrackAccountId: nil)
            }
            try await plaid.exchangeToken(
                publicToken: publicToken,
                institutionName: metadata.institution?.name ?? "Banque",
                accounts: accounts
            )
            // Close the Plaid sheet, then auto-open mapping.
            showPlaidLink = false
            if let newItem = plaid.connectedItems.last {
                itemToMap = newItem
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func syncAll() async {
        isSyncing = true
        syncResults = await PlaidSyncEngine.shared.syncAll(context: context)
        isSyncing = false
        showSyncSummary = true
    }

    private func accountIcon(type: String) -> String {
        switch type.lowercased() {
        case "depository": return "building.columns.fill"
        case "credit":     return "creditcard.fill"
        case "investment": return "chart.line.uptrend.xyaxis"
        case "loan":       return "banknote.fill"
        default:           return "dollarsign.circle.fill"
        }
    }
}

// MARK: - PlaidLinkMetadata

struct PlaidLinkMetadata {
    struct Account {
        let id:           String
        let name:         String
        let officialName: String?
        let type:         String
        let subtype:      String?
        let mask:         String?
    }
    struct Institution {
        let id:   String
        let name: String
    }
    let accounts:    [Account]
    let institution: Institution?
    let linkSessionId: String
}

// MARK: - PlaidLinkView (Hosted Link via ASWebAuthenticationSession)

import AuthenticationServices

/// Opens Plaid Hosted Link in a secure ASWebAuthenticationSession (required
/// by Plaid for webview apps). Plaid hosts the entire flow; on completion we
/// poll the backend for the public_token — no postMessage parsing.
struct PlaidLinkView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LanguageManager.self) private var lang
    let onSuccess: (String, PlaidLinkMetadata) -> Void

    @State private var status: String = ""
    @State private var error: String? = nil
    @State private var controller = WebAuthController()

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let err = error {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40)).foregroundStyle(.orange)
                    Text(err).multilineTextAlignment(.center).foregroundStyle(.secondary)
                    Button(lang["action.cancel"]) { dismiss() }.buttonStyle(.bordered)
                } else {
                    ProgressView()
                    Text(status.isEmpty ? lang["plaid.connecting"] : status)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(lang["plaid.connect.title"])
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(lang["action.cancel"]) { dismiss() }
                }
            }
        }
        .task { await start() }
    }

    private func start() async {
        do {
            status = lang["plaid.connecting"]
            let (hostedURL, linkToken) = try await PlaidManager.shared.createHostedLink()

            // Open the hosted flow. Plaid redirects to a plaidlink:// URL on finish.
            try await controller.authenticate(urlString: hostedURL, scheme: "fintrack")

            // Session finished — poll for the public_token (Plaid needs a moment).
            status = lang["plaid.connecting"]
            var token: String? = nil
            for _ in 0..<10 {
                token = try await PlaidManager.shared.fetchLinkResult(linkToken: linkToken)
                if token != nil { break }
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
            guard let publicToken = token else {
                error = lang["plaid.connected.error"]; return
            }
            onSuccess(publicToken, PlaidLinkMetadata(accounts: [], institution: nil, linkSessionId: ""))
        } catch let e as ASWebAuthenticationSessionError where e.code == .canceledLogin {
            dismiss()  // user closed the sheet
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Bridges ASWebAuthenticationSession to async/await.
@MainActor
final class WebAuthController: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func authenticate(urlString: String, scheme: String) async throws {
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let s = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { _, error in
                if let error { cont.resume(throwing: error) }
                else { cont.resume() }
            }
            s.presentationContextProvider = self
            s.prefersEphemeralWebBrowserSession = false
            self.session = s
            s.start()
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first?.keyWindow ?? ASPresentationAnchor()
    }
}

// MARK: - AccountMappingView

struct AccountMappingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LanguageManager.self) private var lang
    @State private var plaid = PlaidManager.shared
    @Environment(EntitlementManager.self) private var entitlements

    var item: PlaidConnectedItem
    let fintrackAccounts: [Account]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(lang["plaid.map.subtitle"])
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                ForEach(item.accounts) { plaidAcc in
                    Section(plaidAcc.name + (plaidAcc.mask.map { " •••\($0)" } ?? "")) {
                        // "Don't import" row
                        mappingRow(
                            title: lang["plaid.map.none"],
                            systemImage: "nosign",
                            tint: .secondary,
                            isSelected: plaidAcc.fintrackAccountId == nil
                        ) {
                            plaid.clearAccountMapping(itemId: item.id, plaidAccountId: plaidAcc.id)
                        }

                        // One row per compatible FinTrack account
                        ForEach(compatibleAccounts(for: plaidAcc)) { acc in
                            mappingRow(
                                title: acc.name,
                                subtitle: acc.currency,
                                systemImage: acc.iconSystemName,
                                tint: Color(hex: acc.colorHex),
                                isSelected: plaidAcc.fintrackAccountId == acc.uuid
                            ) {
                                plaid.updateAccountMapping(
                                    itemId: item.id,
                                    plaidAccountId: plaidAcc.id,
                                    fintrackAccountId: acc.uuid
                                )
                            }
                        }
                    }
                }
            }
            .navigationTitle(lang["plaid.map.title"])
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(lang["action.close"]) { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    @ViewBuilder
    private func mappingRow(title: String,
                            subtitle: String? = nil,
                            systemImage: String,
                            tint: Color,
                            isSelected: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                    .frame(width: 24)
                Text(title)
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text("(\(subtitle))").foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                        .fontWeight(.semibold)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func compatibleAccounts(for plaidAcc: PlaidAccountMeta) -> [Account] {
        // Filter by approximate type compatibility
        switch plaidAcc.type.lowercased() {
        case "credit": return fintrackAccounts.filter { $0.type == .credit }
        case "loan":   return fintrackAccounts.filter { $0.type == .investment || $0.type == .other }
        default:       return fintrackAccounts.filter { $0.type != .credit }
        }
    }
}
