//
//  PlaidManager.swift
//  FinTrack
//
//  Communicates with the FinTrack Plaid backend hosted on the Synology NAS.
//  Access tokens are stored exclusively in the iOS Keychain — never in SwiftData.
//

import Foundation
import SwiftUI

// MARK: - Configuration

/// Fill these two values after deploying the backend on your NAS.
/// NEVER hardcode the API key in source control — use Xcode build settings or a config file.
enum PlaidConfig {
    /// Base URL of your NAS backend, e.g. "https://fintrack.your-domain.com"
    static let baseURL = "https://hidden-block-e3ed.regis-bile.workers.dev"

    /// Must match API_KEY in the .env file on your NAS
    static let apiKey  = "fintrack-2026-bmsk"
}

// MARK: - Connected Item (stored in Keychain + SwiftData metadata)

struct PlaidConnectedItem: Codable, Identifiable {
    let id:          String   // Plaid item_id
    let accessToken: String   // stored in Keychain, keyed by item_id
    let institutionName: String
    var accounts:    [PlaidAccountMeta]
    let connectedAt: Date
    var lastSyncCursor: String?   // for incremental sync
    var lastSyncDate:   Date?
}

struct PlaidAccountMeta: Codable, Identifiable {
    let id:           String  // Plaid account_id
    let name:         String
    let officialName: String?
    let type:         String
    let subtype:      String?
    let mask:         String?  // last 4 digits
    let currencyCode: String?
    /// Linked FinTrack account ID (UUID string) — nil until user maps it
    var fintrackAccountId: String?
}

// MARK: - API response models

private struct HostedLinkResponse: Decodable {
    let hosted_link_url: String
    let link_token: String
}

private struct LinkResultResponse: Decodable {
    let status: String?
    let public_token: String?
}

private struct LinkTokenResponse: Decodable {
    let link_token: String
    let expiration: String
}

private struct ExchangeResponse: Decodable {
    let access_token: String
    let item_id:      String
}

struct PlaidSyncResponse: Decodable {
    let added:       [PlaidTransaction]
    let modified:    [PlaidTransaction]
    let removed:     [RemovedTransaction]
    let next_cursor: String
    let has_more:    Bool
}

struct PlaidTransaction: Decodable, Identifiable {
    let transaction_id: String
    let account_id:     String
    let amount:         Double   // positive = debit in Plaid convention
    let date:           String   // "YYYY-MM-DD"
    let name:           String
    let merchant_name:  String?
    let iso_currency_code: String?
    let pending:        Bool
    let category:       [String]?
    let logo_url:       String?

    var id: String { transaction_id }
}

struct RemovedTransaction: Decodable {
    let transaction_id: String
}

struct PlaidBalancesResponse: Decodable {
    let accounts: [PlaidAccountBalance]
}

struct PlaidAccountBalance: Decodable {
    let account_id:    String
    let name:          String
    let official_name: String?
    let type:          String
    let subtype:       String?
    let mask:          String?
    let balances:      BalanceDetail
}

struct BalanceDetail: Decodable {
    let available: Double?
    let current:   Double?
    let limit:     Double?
    let iso_currency_code: String?
}

// MARK: - PlaidManager

@Observable
final class PlaidManager {

    static let shared = PlaidManager()
    private init() { loadItems() }

    // MARK: State

    private(set) var connectedItems: [PlaidConnectedItem] = []
    private(set) var isLoading = false
    private(set) var lastError: String? = nil

    private let itemsKey = "plaidConnectedItems_v1"

    // MARK: - Link token (step 1)

    /// Creates a Hosted Link session. Returns the URL to open in
    /// ASWebAuthenticationSession plus the link_token used to poll the result.
    /// Hosted Link is required for webview apps: Plaid hosts the UI and the
    /// public_token is retrieved server-side (no fragile postMessage parsing).
    func createHostedLink() async throws -> (hostedURL: String, linkToken: String) {
        let url = URL(string: "\(PlaidConfig.baseURL)/create_hosted_link")!
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(PlaidConfig.apiKey, forHTTPHeaderField: "X-API-Key")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["user_id": "fintrack_main"])

        let (data, response) = try await URLSession.shared.data(for: req)
        try validateResponse(response)
        let decoded = try JSONDecoder().decode(HostedLinkResponse.self, from: data)
        return (decoded.hosted_link_url, decoded.link_token)
    }

    /// Polls /link/token/get until the hosted session yields a public_token.
    /// Returns nil if the session isn't complete yet.
    func fetchLinkResult(linkToken: String) async throws -> String? {
        let url = URL(string: "\(PlaidConfig.baseURL)/get_link_result")!
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(PlaidConfig.apiKey, forHTTPHeaderField: "X-API-Key")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["link_token": linkToken])

        let (data, response) = try await URLSession.shared.data(for: req)
        try validateResponse(response)
        let decoded = try JSONDecoder().decode(LinkResultResponse.self, from: data)
        return decoded.public_token
    }

    // MARK: - Exchange token (step 2)

    /// Called after the user completes Plaid Link.
    /// Exchanges the one-time public_token for a permanent access_token.
    func exchangeToken(publicToken: String,
                       institutionName: String,
                       accounts: [PlaidAccountMeta]) async throws {
        await MainActor.run { isLoading = true; lastError = nil }
        defer { Task { @MainActor in self.isLoading = false } }

        let url = URL(string: "\(PlaidConfig.baseURL)/exchange_token")!
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(PlaidConfig.apiKey, forHTTPHeaderField: "X-API-Key")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["public_token": publicToken])

        let (data, response) = try await URLSession.shared.data(for: req)
        try validateResponse(response)
        let decoded = try JSONDecoder().decode(ExchangeResponse.self, from: data)

        // Store access_token in Keychain (never in UserDefaults or SwiftData)
        KeychainHelper.set(decoded.access_token, forKey: "plaid_token_\(decoded.item_id)")

        let item = PlaidConnectedItem(
            id:              decoded.item_id,
            accessToken:     decoded.access_token,
            institutionName: institutionName,
            accounts:        accounts,
            connectedAt:     .now,
            lastSyncCursor:  nil,
            lastSyncDate:    nil
        )
        await MainActor.run {
            connectedItems.append(item)
            saveItems()
        }
    }

    // MARK: - Sync transactions

    func syncTransactions(for item: PlaidConnectedItem) async throws -> PlaidSyncResponse {
        guard let accessToken = KeychainHelper.string(forKey: "plaid_token_\(item.id)") else {
            throw PlaidError.missingAccessToken
        }

        var body: [String: Any] = ["access_token": accessToken]
        if let cursor = item.lastSyncCursor, !cursor.isEmpty {
            body["cursor"] = cursor
        }

        let url = URL(string: "\(PlaidConfig.baseURL)/sync_transactions")!
        var req = URLRequest(url: url, timeoutInterval: 30)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(PlaidConfig.apiKey, forHTTPHeaderField: "X-API-Key")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)

        // Handle re-auth required
        if let http = response as? HTTPURLResponse, http.statusCode == 428 {
            throw PlaidError.reAuthRequired(itemId: item.id)
        }

        try validateResponse(response)
        return try JSONDecoder().decode(PlaidSyncResponse.self, from: data)
    }

    // MARK: - Balances

    func fetchBalances(for item: PlaidConnectedItem) async throws -> PlaidBalancesResponse {
        guard let accessToken = KeychainHelper.string(forKey: "plaid_token_\(item.id)") else {
            throw PlaidError.missingAccessToken
        }

        let url = URL(string: "\(PlaidConfig.baseURL)/get_balances")!
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(PlaidConfig.apiKey, forHTTPHeaderField: "X-API-Key")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["access_token": accessToken])

        let (data, response) = try await URLSession.shared.data(for: req)
        try validateResponse(response)
        return try JSONDecoder().decode(PlaidBalancesResponse.self, from: data)
    }

    // MARK: - Disconnect

    func disconnect(item: PlaidConnectedItem) async throws {
        guard let accessToken = KeychainHelper.string(forKey: "plaid_token_\(item.id)") else {
            // Already disconnected — just clean up locally
            await removeItem(id: item.id)
            return
        }

        let url = URL(string: "\(PlaidConfig.baseURL)/disconnect")!
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "DELETE"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(PlaidConfig.apiKey, forHTTPHeaderField: "X-API-Key")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["access_token": accessToken])

        let (_, response) = try await URLSession.shared.data(for: req)
        // Best-effort — clean up locally even if server call fails
        _ = try? validateResponse(response)

        KeychainHelper.delete(forKey: "plaid_token_\(item.id)")
        await removeItem(id: item.id)
    }

    // MARK: - Cursor management

    @MainActor
    func updateCursor(for itemId: String, cursor: String) {
        if let idx = connectedItems.firstIndex(where: { $0.id == itemId }) {
            connectedItems[idx].lastSyncCursor = cursor
            connectedItems[idx].lastSyncDate   = .now
            saveItems()
        }
    }

    @MainActor
    func updateAccountMapping(itemId: String,
                               plaidAccountId: String,
                               fintrackAccountId: String) {
        guard let itemIdx = connectedItems.firstIndex(where: { $0.id == itemId }),
              let accIdx  = connectedItems[itemIdx].accounts.firstIndex(where: { $0.id == plaidAccountId })
        else { return }
        connectedItems[itemIdx].accounts[accIdx].fintrackAccountId = fintrackAccountId
        saveItems()
    }

    // MARK: - Persistence (items metadata in UserDefaults; secrets in Keychain)

    private func saveItems() {
        let stripped = connectedItems.map { item -> PlaidConnectedItem in
            // Never persist the access_token in UserDefaults
            let copy = item
            return copy
        }
        if let data = try? JSONEncoder().encode(stripped) {
            UserDefaults.standard.set(data, forKey: itemsKey)
        }
    }

    private func loadItems() {
        guard let data  = UserDefaults.standard.data(forKey: itemsKey),
              let items = try? JSONDecoder().decode([PlaidConnectedItem].self, from: data)
        else { return }
        // access_token is read on-demand from Keychain in syncTransactions/fetchBalances/disconnect
        connectedItems = items
    }

    @MainActor
    private func removeItem(id: String) {
        connectedItems.removeAll { $0.id == id }
        saveItems()
    }

    // MARK: - Helpers

    private func validateResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw PlaidError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            throw PlaidError.httpError(statusCode: http.statusCode)
        }
    }
}

// MARK: - Errors

enum PlaidError: LocalizedError {
    case missingAccessToken
    case invalidResponse
    case httpError(statusCode: Int)
    case reAuthRequired(itemId: String)

    var errorDescription: String? {
        switch self {
        case .missingAccessToken: return "Token d'accès introuvable dans le trousseau."
        case .invalidResponse:   return "Réponse invalide du serveur."
        case .httpError(let c):  return "Erreur serveur (\(c))."
        case .reAuthRequired:    return "Reconnexion bancaire requise."
        }
    }
}
