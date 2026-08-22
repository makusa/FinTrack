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
    @State private var discrepancies:     [PlaidSyncEngine.BalanceDiscrepancy] = []
    @State private var discrepancyToAdjust: PlaidSyncEngine.BalanceDiscrepancy? = nil
    @State private var showReview         = false

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
                            syncResultRow(result)
                        }
                        let toReview = syncResults.reduce(0) { $0 + $1.flagged }
                        if toReview > 0 {
                            Button {
                                showReview = true
                            } label: {
                                Label("\(toReview) \(lang["flinks.sync.review"])", systemImage: "checklist")
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }

                // ── Balance discrepancies (drift detected on a recent sync) ─
                if !discrepancies.isEmpty {
                    Section {
                        ForEach(discrepancies) { d in
                            VStack(alignment: .leading, spacing: 6) {
                                Label(d.accountName, systemImage: "exclamationmark.triangle.fill")
                                    .font(.callout.weight(.medium))
                                    .foregroundStyle(.orange)
                                Text("\(lang["flinks.balance.bankSays"]) : \(d.check.ledgerBalance.formatted(asCurrency: d.check.currency))")
                                    .font(.caption).foregroundStyle(.secondary)
                                Text("\(lang["flinks.balance.gap"]) : \(d.check.delta.formatted(asCurrency: d.check.currency))")
                                    .font(.caption).foregroundStyle(.secondary)
                                Button {
                                    discrepancyToAdjust = d
                                } label: {
                                    Label(lang["flinks.balance.adjust"], systemImage: "equal.circle")
                                }
                                .buttonStyle(.borderless)
                                .padding(.top, 2)
                            }
                            .padding(.vertical, 2)
                        }
                    } header: {
                        Text(lang["flinks.balance.section"])
                    } footer: {
                        Text(lang["flinks.balance.explain"])
                    }
                }

                // ── Info footer ────────────────────────────────────────────
                Section {
                    Label(lang["plaid.security.note"], systemImage: "lock.shield")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                #if DEBUG
                Section {
                    NavigationLink {
                        PlaidDebugView()
                    } label: {
                        Label("Débogage : données Plaid", systemImage: "ladybug")
                    }
                } footer: {
                    Text("Affiche les soldes bruts renvoyés par Plaid (build debug uniquement).")
                }
                #endif
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
                AccountMappingView(item: item)
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
            .alert(lang["flinks.balance.adjust.confirm.title"],
                   isPresented: Binding(get: { discrepancyToAdjust != nil },
                                        set: { if !$0 { discrepancyToAdjust = nil } }),
                   presenting: discrepancyToAdjust) { d in
                Button(lang["flinks.balance.adjust"]) { adjust(d) }
                Button(lang["action.cancel"], role: .cancel) { discrepancyToAdjust = nil }
            } message: { d in
                Text(String(format: lang["flinks.balance.adjust.confirm.msg"], d.accountName))
            }
            .sheet(isPresented: $showReview) {
                DuplicateReviewView()
            }
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "building.columns")
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

    @ViewBuilder
    private func syncResultRow(_ result: PlaidSyncEngine.SyncResult) -> some View {
        let inst = plaid.connectedItems.first { $0.id == result.itemId }?.institutionName ?? result.itemId
        let ok = result.error == nil
        let summary = "+\(result.added) · ~\(result.modified) · -\(result.removed)"
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(ok ? .green : .red)
            VStack(alignment: .leading, spacing: 2) {
                Text(inst)
                    .font(.callout.weight(.medium))
                if let err = result.error {
                    Text(err.localizedDescription)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if result.reconciled > 0 {
                        Text("\(result.reconciled) \(lang["flinks.sync.reconciled"])")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if result.flagged > 0 {
                        Text("\(result.flagged) \(lang["flinks.sync.review"])")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
    }

    private func syncAll() async {
        isSyncing = true
        syncResults = await PlaidSyncEngine.shared.syncAll(context: context)
        discrepancies = syncResults.flatMap { $0.discrepancies }
        isSyncing = false
        showSyncSummary = true
    }

    /// Aligns the account balance on the real bank balance (correction transaction
    /// or opening-balance shift, decided by OFXImportService).
    private func adjust(_ d: PlaidSyncEngine.BalanceDiscrepancy) {
        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        guard let account = accounts.first(where: { $0.uuid == d.accountUuid }) else { return }
        OFXImportService.applyBalanceAdjustment(d.check, account: account, context: context,
                                                adjustmentLabel: lang["flinks.balance.adjustment.label"])
        discrepancies.removeAll { $0.id == d.id }
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
    @Environment(\.modelContext) private var context
    @Environment(LanguageManager.self) private var lang
    @State private var plaid = PlaidManager.shared

    // Reactive query so the list updates instantly when we create an account.
    @Query(filter: #Predicate<Account> { !$0.isArchived }, sort: \Account.createdAt)
    private var fintrackAccounts: [Account]

    var item: PlaidConnectedItem

    // Local mirror of the item so menu selections re-render immediately.
    @State private var mappings: [String: String?] = [:]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(lang["plaid.map.subtitle"])
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Section {
                    ForEach(item.accounts) { plaidAcc in
                        accountRow(plaidAcc)
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
            .onAppear(perform: loadMappings)
        }
    }

    // MARK: - One compact row per Plaid account

    @ViewBuilder
    private func accountRow(_ plaidAcc: PlaidAccountMeta) -> some View {
        let currentId = mappings[plaidAcc.id] ?? plaidAcc.fintrackAccountId
        let linked = currentId.flatMap { id in fintrackAccounts.first { $0.uuid == id } }

        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(plaidAcc.name)
                    .font(.body)
                    .lineLimit(1)
                if let mask = plaidAcc.mask {
                    Text("•••\(mask)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 8)
            destinationMenu(for: plaidAcc, linked: linked, isUnmapped: currentId == nil)
        }
    }

    // MARK: - The dropdown (native Menu — fast, opens on tap only)

    @ViewBuilder
    private func destinationMenu(for plaidAcc: PlaidAccountMeta,
                                 linked: Account?,
                                 isUnmapped: Bool) -> some View {
        Menu {
            menuContent(for: plaidAcc)
        } label: {
            menuLabel(linked: linked, isUnmapped: isUnmapped)
        }
    }

    @ViewBuilder
    private func menuContent(for plaidAcc: PlaidAccountMeta) -> some View {
        Button {
            setMapping(plaidAcc, to: nil)
        } label: {
            Label(lang["plaid.map.none"], systemImage: "circle.slash")
        }

        Divider()

        ForEach(compatibleAccounts(for: plaidAcc)) { acc in
            Button {
                setMapping(plaidAcc, to: acc.uuid)
            } label: {
                Label(acc.name, systemImage: acc.iconSystemName)
            }
        }

        Divider()

        Button {
            createAndMap(plaidAcc)
        } label: {
            Label(lang["plaid.map.create"], systemImage: "plus.circle")
        }
    }

    @ViewBuilder
    private func menuLabel(linked: Account?, isUnmapped: Bool) -> some View {
        HStack(spacing: 6) {
            if let acc = linked {
                Circle()
                    .fill(Color(hex: acc.colorHex))
                    .frame(width: 16, height: 16)
                Text(acc.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
            } else if isUnmapped {
                Text(lang["plaid.map.none"])
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text(lang["plaid.map.choose"])
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.tint)
            }
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.tertiarySystemFill), in: Capsule())
        .frame(maxWidth: 170, alignment: .trailing)
    }

    // MARK: - Actions

    private func loadMappings() {
        for acc in item.accounts {
            mappings[acc.id] = acc.fintrackAccountId
        }
    }

    private func setMapping(_ plaidAcc: PlaidAccountMeta, to uuid: String?) {
        mappings[plaidAcc.id] = uuid
        if let uuid {
            plaid.updateAccountMapping(itemId: item.id,
                                       plaidAccountId: plaidAcc.id,
                                       fintrackAccountId: uuid)
        } else {
            plaid.clearAccountMapping(itemId: item.id, plaidAccountId: plaidAcc.id)
        }
    }

    /// Instantly create a FinTrack account pre-filled from the Plaid account,
    /// then map to it. No confirmation — user can edit later.
    private func createAndMap(_ plaidAcc: PlaidAccountMeta) {
        let type = accountType(for: plaidAcc)
        // Pick a color deterministically from the palette based on existing count.
        let palette = ColorPalette.accountColors
        let color = palette[fintrackAccounts.count % palette.count]

        let account = Account(
            name: plaidAcc.name,
            institution: item.institutionName,
            type: type,
            currency: plaidAcc.currencyCode ?? Currencies.default,
            initialBalance: 0,
            colorHex: color,
            iconSystemName: type.defaultIconSystemName,
            notes: nil
        )
        context.insert(account)
        try? context.save()

        // Map to the freshly created account (its uuid default is set on init).
        setMapping(plaidAcc, to: account.uuid)
    }

    /// Maps a Plaid account type/subtype to a FinTrack AccountType.
    private func accountType(for plaidAcc: PlaidAccountMeta) -> AccountType {
        switch plaidAcc.type.lowercased() {
        case "credit":      return .credit
        case "loan":        return .other
        case "investment":  return .investment
        case "depository":
            switch (plaidAcc.subtype ?? "").lowercased() {
            case "savings", "cd", "money market": return .savings
            default:                              return .checking
            }
        default:            return .other
        }
    }

    private func compatibleAccounts(for plaidAcc: PlaidAccountMeta) -> [Account] {
        // Only propose FinTrack accounts of the same currency — mapping a CAD bank
        // account onto a USD account would corrupt balances. When Plaid reports no
        // currency, fall back to no currency filter (best effort).
        let sameCurrency: (Account) -> Bool = { acc in
            guard let cur = plaidAcc.currencyCode else { return true }
            return acc.currency == cur
        }
        switch plaidAcc.type.lowercased() {
        case "credit": return fintrackAccounts.filter { $0.type == .credit && sameCurrency($0) }
        case "loan":   return fintrackAccounts.filter { ($0.type == .investment || $0.type == .other) && sameCurrency($0) }
        default:       return fintrackAccounts.filter { $0.type != .credit && sameCurrency($0) }
        }
    }
}
#if DEBUG
// MARK: - Developer: raw Plaid balances

struct PlaidDebugView: View {
    @Environment(\.modelContext) private var context
    @State private var plaid = PlaidManager.shared
    @State private var output: String = ""
    @State private var loading = false
    @State private var txOutput: String = ""
    @State private var txLoading = false

    var body: some View {
        List {
            Section {
                Button {
                    Task { await fetchAll() }
                } label: {
                    HStack {
                        Label("Récupérer les soldes Plaid", systemImage: "arrow.down.circle")
                        if loading { Spacer(); ProgressView() }
                    }
                }
                .disabled(loading)
                Button {
                    Task { await fetchTransactions() }
                } label: {
                    HStack {
                        Label("Récupérer les transactions", systemImage: "list.bullet.rectangle")
                        if txLoading { Spacer(); ProgressView() }
                    }
                }
                .disabled(txLoading)
            } footer: {
                Text("Sans effet de bord : les transactions sont relues depuis zéro sans avancer le curseur de synchronisation.")
            }
            if !output.isEmpty {
                Section("Soldes (/get_balances)") {
                    Text(output)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            if !txOutput.isEmpty {
                Section("Transactions (/sync_transactions)") {
                    Text(txOutput)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
        .navigationTitle("Données Plaid")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func fetchAll() async {
        loading = true
        defer { loading = false }
        guard !plaid.connectedItems.isEmpty else {
            output = "Aucun établissement connecté."
            return
        }
        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        var lines: [String] = []
        for item in plaid.connectedItems {
            lines.append("═══ \(item.institutionName) ═══")
            do {
                let resp = try await plaid.fetchBalances(for: item)
                for acc in resp.accounts {
                    lines.append("• \(acc.name)  [\(acc.type)/\(acc.subtype ?? "—")]")
                    lines.append("   account_id: \(acc.account_id)")
                    if let m = acc.mask { lines.append("   mask: ••\(m)") }
                    lines.append("   current:   \(acc.balances.current.map { String($0) } ?? "nil")")
                    lines.append("   available: \(acc.balances.available.map { String($0) } ?? "nil")")
                    lines.append("   limit:     \(acc.balances.limit.map { String($0) } ?? "nil")")
                    lines.append("   devise:    \(acc.balances.iso_currency_code ?? "nil")")
                    if let mappedId = item.accounts.first(where: { $0.id == acc.account_id })?.fintrackAccountId,
                       let ftAcc = accounts.first(where: { $0.uuid == mappedId }) {
                        lines.append("   → mappé: \(ftAcc.name) — solde app: \(ftAcc.balance)")
                    } else {
                        lines.append("   → non mappé")
                    }
                    lines.append("")
                }
            } catch {
                lines.append("⚠️ Erreur: \(error)")
                lines.append("")
            }
        }
        output = lines.joined(separator: "\n")
    }

    private func fetchTransactions() async {
        txLoading = true
        defer { txLoading = false }
        guard !plaid.connectedItems.isEmpty else {
            txOutput = "Aucun établissement connecté."
            return
        }
        var lines: [String] = []
        for item in plaid.connectedItems {
            lines.append("═══ \(item.institutionName) ═══")
            do {
                let txs = try await plaid.debugFetchAllTransactions(for: item)
                lines.append("\(txs.count) transactions (added, curseur vide)")
                // Convention Plaid : amount positif = débit (sortie).
                let byAccount = Dictionary(grouping: txs, by: { $0.account_id })
                for (accId, group) in byAccount.sorted(by: { $0.key < $1.key }) {
                    let sum = group.reduce(0.0) { $0 + $1.amount }
                    lines.append("  …\(accId.suffix(6)) : \(group.count) tx · somme débits \(sum)")
                }
                lines.append("")
                for t in txs.sorted(by: { $0.date > $1.date }) {
                    let sign = t.amount >= 0 ? "−" : "+"   // +amount Plaid = débit
                    let pend = t.pending ? "  ⏳" : ""
                    lines.append("\(t.date)  \(sign)\(abs(t.amount)) \(t.iso_currency_code ?? "?")  \(t.name)\(pend)")
                }
            } catch {
                lines.append("⚠️ Erreur: \(error)")
            }
            lines.append("")
        }
        txOutput = lines.joined(separator: "\n")
    }
}
#endif
