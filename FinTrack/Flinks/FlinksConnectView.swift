//
//  FlinksConnectView.swift
//  FinTrack
//
//  - BankSyncView           — list of connected bank logins + sync controls
//  - FlinksConnectWebView   — WKWebView hosting Flinks Connect; captures the
//                             REDIRECT event carrying the LoginId
//

import SwiftUI
import SwiftData
import WebKit

// MARK: - Connected logins screen

struct BankSyncView: View {
    @Environment(LanguageManager.self) private var lang
    @Environment(\.modelContext) private var context

    @State private var manager = FlinksManager.shared
    @State private var showConnect = false
    @State private var syncMessage: String? = nil
    @State private var loginToDelete: FlinksConnectedLogin? = nil

    var body: some View {
        List {
            Section {
                if manager.connectedLogins.isEmpty {
                    ContentUnavailableView(
                        lang["flinks.none"],
                        systemImage: "building.columns.badge.plus",
                        description: Text(lang["flinks.none.sub"])
                    )
                } else {
                    ForEach(manager.connectedLogins) { login in
                        loginRow(login)
                    }
                }
            } footer: {
                Text(lang["flinks.footer"])
            }

            Section {
                Button {
                    showConnect = true
                } label: {
                    Label(lang["flinks.connect"], systemImage: "plus.circle.fill")
                }

                if !manager.connectedLogins.isEmpty {
                    Button {
                        Task { await syncAll() }
                    } label: {
                        HStack {
                            Label(lang["flinks.syncNow"], systemImage: "arrow.triangle.2.circlepath")
                            if manager.isSyncing {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(manager.isSyncing)
                }
            }

            if let msg = syncMessage {
                Section {
                    Text(msg)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(lang["flinks.title"])
        .sheet(isPresented: $showConnect) {
            NavigationStack {
                FlinksConnectWebView { loginId, institution in
                    Task { await handleConnected(loginId: loginId, institution: institution) }
                }
                .navigationTitle(lang["flinks.connect"])
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(lang["action.cancel"]) { showConnect = false }
                    }
                }
            }
        }
        .confirmationDialog(
            lang["flinks.disconnect.confirm"],
            isPresented: Binding(get: { loginToDelete != nil },
                                 set: { if !$0 { loginToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button(lang["action.delete"], role: .destructive) {
                if let login = loginToDelete {
                    manager.removeLogin(id: login.id)
                }
                loginToDelete = nil
            }
            Button(lang["action.cancel"], role: .cancel) { loginToDelete = nil }
        }
    }

    private func loginRow(_ login: FlinksConnectedLogin) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "building.columns.fill")
                    .foregroundStyle(.tint)
                Text(login.institutionName)
                    .font(.body.weight(.medium))
                Spacer()
                Menu {
                    Button(role: .destructive) {
                        loginToDelete = login
                    } label: {
                        Label(lang["flinks.disconnect"], systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            Text("\(login.accounts.count) \(lang["flinks.accounts"])")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let last = login.lastSyncDate {
                Text("\(lang["flinks.lastSync"]) \(last.appFormattedRelative())")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private func handleConnected(loginId: String, institution: String) async {
        showConnect = false
        do {
            let requestId = try await manager.authorize(loginId: loginId)
            let detail = try await manager.getAccountsDetail(requestId: requestId)
            let accounts = detail.accounts.map { acc in
                FlinksAccountMeta(
                    id: acc.id,
                    title: acc.title ?? lang["flinks.account"],
                    accountNumber: acc.accountNumber,
                    category: acc.category,
                    currency: acc.currency,
                    fintrackAccountId: nil
                )
            }
            let login = FlinksConnectedLogin(
                id: loginId,
                institutionName: institution.isEmpty
                    ? (detail.accounts.first?.institutionName ?? "Banque")
                    : institution,
                accounts: accounts,
                connectedAt: .now,
                lastSyncDate: nil
            )
            manager.addLogin(login)
            syncMessage = lang["flinks.connected.ok"]
        } catch {
            syncMessage = lang["flinks.connected.error"]
        }
    }

    private func syncAll() async {
        manager.isSyncing = true
        defer { manager.isSyncing = false }
        let results = await FlinksSyncEngine.shared.syncAll(context: context)
        let added = results.reduce(0) { $0 + $1.added }
        let reconciled = results.reduce(0) { $0 + $1.reconciled }
        let flagged = results.reduce(0) { $0 + $1.flagged }
        var msg = "\(lang["flinks.sync.done"]) \(added)"
        if reconciled > 0 { msg += " · \(reconciled) \(lang["flinks.sync.reconciled"])" }
        if flagged > 0 { msg += " · \(flagged) \(lang["flinks.sync.review"])" }
        syncMessage = msg
    }
}

// MARK: - Flinks Connect WebView

struct FlinksConnectWebView: UIViewRepresentable {
    /// Called with (loginId, institutionName) on successful connection.
    let onSuccess: (String, String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSuccess: onSuccess) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()

        // Forward window.postMessage events to native code.
        let script = """
        window.addEventListener('message', function(e) {
            window.webkit.messageHandlers.flinks.postMessage(JSON.stringify(e.data));
        });
        """
        config.userContentController.addUserScript(
            WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        )
        config.userContentController.add(context.coordinator, name: "flinks")

        let webView = WKWebView(frame: .zero, configuration: config)
        if let url = URL(string: FlinksConfig.connectURL) {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKScriptMessageHandler {
        let onSuccess: (String, String) -> Void
        private var delivered = false

        init(onSuccess: @escaping (String, String) -> Void) {
            self.onSuccess = onSuccess
        }

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard !delivered,
                  let json = message.body as? String,
                  let data = json.data(using: .utf8),
                  let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return }

            // Flinks Connect emits { step: "REDIRECT", loginId: "...", institution: "..." }
            let step = (payload["step"] as? String) ?? ""
            if step == "REDIRECT", let loginId = payload["loginId"] as? String {
                delivered = true
                let institution = (payload["institution"] as? String) ?? ""
                onSuccess(loginId, institution)
            }
        }
    }
}
