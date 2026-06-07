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
            if !entitlements.hasPlaid {
                ProGateView(feature: .plaidSync)
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
                             date.formatted(.relative(presentation: .named)))
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
            // Auto-open mapping after connection
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

// MARK: - PlaidLinkView (WKWebView wrapping Plaid Link)

struct PlaidLinkView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LanguageManager.self) private var lang
    let onSuccess: (String, PlaidLinkMetadata) -> Void

    @State private var linkToken: String? = nil
    @State private var isLoading = true
    @State private var error: String? = nil

    var body: some View {
        NavigationStack {
            Group {
                if let token = linkToken {
                    PlaidWebView(linkToken: token, onSuccess: onSuccess, onExit: { dismiss() })
                } else if let err = error {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 40))
                            .foregroundStyle(.orange)
                        Text(err)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                        Button(lang["action.cancel"]) { dismiss() }
                            .buttonStyle(.bordered)
                    }
                    .padding()
                } else {
                    ProgressView(lang["plaid.connecting"])
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle(lang["plaid.connect.title"])
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(lang["action.cancel"]) { dismiss() }
                }
            }
        }
        .task { await loadLinkToken() }
    }

    private func loadLinkToken() async {
        do {
            linkToken = try await PlaidManager.shared.fetchLinkToken()
            isLoading = false
        } catch {
            self.error = error.localizedDescription
            isLoading  = false
        }
    }
}

// MARK: - PlaidWebView

/// WKWebView that loads Plaid Link via the hosted redirect flow.
/// When Plaid calls plaidlink://handoff?public_token=..., we capture it.
struct PlaidWebView: UIViewRepresentable {
    let linkToken: String
    let onSuccess: (String, PlaidLinkMetadata) -> Void
    let onExit:    () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSuccess: onSuccess, onExit: onExit) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let web    = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator

        // Build Plaid Link redirect URL
        // Plaid's redirect-based Link: https://cdn.plaid.com/link/v2/stable/link.html
        let urlStr = "https://cdn.plaid.com/link/v2/stable/link.html?token=\(linkToken)"
        if let url = URL(string: urlStr) {
            web.load(URLRequest(url: url))
        }
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onSuccess: (String, PlaidLinkMetadata) -> Void
        let onExit:    () -> Void

        init(onSuccess: @escaping (String, PlaidLinkMetadata) -> Void,
             onExit:    @escaping () -> Void) {
            self.onSuccess = onSuccess
            self.onExit    = onExit
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else {
                decisionHandler(.allow); return
            }

            // Plaid signals success via a plaidlink:// URL scheme
            if url.scheme == "plaidlink" {
                handlePlaidCallback(url: url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        private func handlePlaidCallback(url: URL) {
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let queryItems = components.queryItems else { onExit(); return }

            let params = Dictionary(uniqueKeysWithValues: queryItems.compactMap { item in
                item.value.map { (item.name, $0) }
            })

            if url.host == "handoff" || components.path.contains("handoff") {
                guard let publicToken = params["public_token"] else { onExit(); return }

                // Build metadata from URL params (simplified)
                let metadata = PlaidLinkMetadata(
                    accounts:      [],  // populated from item after exchange
                    institution:   params["institution_name"].map {
                        PlaidLinkMetadata.Institution(id: params["institution_id"] ?? "", name: $0)
                    },
                    linkSessionId: params["link_session_id"] ?? ""
                )
                onSuccess(publicToken, metadata)
            } else {
                // User exited
                onExit()
            }
        }
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
                        Picker(lang["plaid.map.to"], selection: Binding(
                            get: { plaidAcc.fintrackAccountId },
                            set: { newVal in
                                if let id = newVal {
                                    plaid.updateAccountMapping(
                                        itemId: item.id,
                                        plaidAccountId: plaidAcc.id,
                                        fintrackAccountId: id
                                    )
                                }
                            }
                        )) {
                            Text(lang["plaid.map.none"]).tag(String?.none)
                            ForEach(compatibleAccounts(for: plaidAcc)) { acc in
                                HStack {
                                    Image(systemName: acc.iconSystemName)
                                        .foregroundStyle(Color(hex: acc.colorHex))
                                    Text(acc.name)
                                    Text("(\(acc.currency))").foregroundStyle(.secondary)
                                }
                                .tag(Optional(acc.persistentModelID.hashValue.description))
                            }
                        }
                        .pickerStyle(.navigationLink)
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

    private func compatibleAccounts(for plaidAcc: PlaidAccountMeta) -> [Account] {
        // Filter by approximate type compatibility
        switch plaidAcc.type.lowercased() {
        case "credit": return fintrackAccounts.filter { $0.type == .credit }
        case "loan":   return fintrackAccounts.filter { $0.type == .investment || $0.type == .other }
        default:       return fintrackAccounts.filter { $0.type != .credit }
        }
    }
}
