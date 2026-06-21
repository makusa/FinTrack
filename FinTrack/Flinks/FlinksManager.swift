//
//  FlinksManager.swift
//  FinTrack
//
//  Communicates with the FinTrack Flinks proxy backend.
//  The proxy holds the Flinks customerId + credentials; the app only ever
//  sees LoginIds. LoginIds are stored in the iOS Keychain — never in SwiftData.
//
//  Flinks flow:
//    1. FlinksConnectWebView shows Flinks Connect → user authenticates with
//       their bank → REDIRECT event carries a LoginId.
//    2. POST {proxy}/flinks/authorize { loginId } → { requestId }
//    3. GET  {proxy}/flinks/accounts/{requestId} → accounts + transactions
//

import Foundation
import SwiftUI
import os

private let flinksLog = Logger(subsystem: "ca.regis.fintrack", category: "flinks")

// MARK: - Configuration

/// Fill these after deploying the proxy (Cloudflare Workers or NAS).
/// NEVER hardcode secrets in source control — the proxy holds them.
enum FlinksConfig {
    /// Base URL of the proxy, e.g. "https://fintrack-flinks.workers.dev"
    static let proxyBaseURL = "https://VOTRE_PROXY_URL_ICI"

    /// Flinks Connect URL for your instance (sandbox by default).
    /// Production: "https://{instance}-iframe.private.fin.ag/v2/"
    static let connectURL = "https://toolbox-iframe.private.fin.ag/v2/"

    /// Shared key matching the proxy's API_KEY environment variable.
    static let apiKey = "VOTRE_API_KEY_ICI"
}

// MARK: - Connected login (Keychain + metadata)

struct FlinksConnectedLogin: Codable, Identifiable {
    let id:              String   // Flinks LoginId
    let institutionName: String
    var accounts:        [FlinksAccountMeta]
    let connectedAt:     Date
    var lastSyncDate:    Date?
}

struct FlinksAccountMeta: Codable, Identifiable {
    let id:           String   // Flinks Account Id
    let title:        String
    let accountNumber: String? // masked
    let category:     String?  // Operations, Savings, Credits…
    let currency:     String?
    /// Linked FinTrack account ID (UUID string) — nil until user maps it
    var fintrackAccountId: String?
}

// MARK: - API response models (proxy passthrough of Flinks JSON)

struct FlinksAuthorizeResponse: Decodable {
    let requestId: String

    enum CodingKeys: String, CodingKey {
        case requestId = "RequestId"
    }
}

struct FlinksAccountsResponse: Decodable {
    let accounts: [FlinksAccount]
    let login: FlinksLoginInfo?

    enum CodingKeys: String, CodingKey {
        case accounts = "Accounts"
        case login    = "Login"
    }
}

struct FlinksLoginInfo: Decodable {
    let id: String?
    enum CodingKeys: String, CodingKey { case id = "Id" }
}

struct FlinksAccount: Decodable, Identifiable {
    let id:            String
    let title:         String?
    let accountNumber: String?
    let category:      String?
    let currency:      String?
    let balance:       FlinksBalance?
    let transactions:  [FlinksTransaction]?
    let institutionName: String?

    enum CodingKeys: String, CodingKey {
        case id = "Id", title = "Title", accountNumber = "AccountNumber"
        case category = "Category", currency = "Currency", balance = "Balance"
        case transactions = "Transactions", institutionName = "InstitutionName"
    }
}

struct FlinksBalance: Decodable {
    let current:   Double?
    let available: Double?
    enum CodingKeys: String, CodingKey { case current = "Current", available = "Available" }
}

struct FlinksTransaction: Decodable, Identifiable {
    let id:          String
    let date:        String    // "yyyy-MM-dd"
    let description: String?
    let debit:       Double?
    let credit:      Double?
    let balance:     Double?

    enum CodingKeys: String, CodingKey {
        case id = "Id", date = "Date", description = "Description"
        case debit = "Debit", credit = "Credit", balance = "Balance"
    }
}

// MARK: - Manager

@Observable
@MainActor
final class FlinksManager {

    static let shared = FlinksManager()
    private init() { loadConnectedLogins() }

    var connectedLogins: [FlinksConnectedLogin] = []
    var isSyncing = false

    private let keychainKey = "fintrack.flinks.logins"

    // MARK: Keychain persistence

    private func loadConnectedLogins() {
        // Prefer the iCloud-synced item (survives reinstall / new device).
        if let data = KeychainHelper.data(forKey: keychainKey, synchronizable: true),
           let decoded = try? JSONDecoder().decode([FlinksConnectedLogin].self, from: data) {
            connectedLogins = decoded
            return
        }
        // Migrate a legacy device-only item so existing connections aren't lost
        // when upgrading to iCloud Keychain storage.
        if let legacy = KeychainHelper.data(forKey: keychainKey),
           let decoded = try? JSONDecoder().decode([FlinksConnectedLogin].self, from: legacy) {
            connectedLogins = decoded
            saveConnectedLogins()                          // re-store as synchronizable
            _ = KeychainHelper.delete(forKey: keychainKey) // drop the device-only copy
        }
    }

    func saveConnectedLogins() {
        guard let data = try? JSONEncoder().encode(connectedLogins) else { return }
        // Synchronizable: bank LoginIds follow the user's iCloud Keychain across
        // devices and survive reinstall (requires iCloud Keychain enabled).
        _ = KeychainHelper.set(data, forKey: keychainKey, synchronizable: true)
    }

    func addLogin(_ login: FlinksConnectedLogin) {
        connectedLogins.removeAll { $0.id == login.id }
        connectedLogins.append(login)
        saveConnectedLogins()
    }

    func removeLogin(id: String) {
        connectedLogins.removeAll { $0.id == id }
        saveConnectedLogins()
    }

    /// Removes ALL bank connections: clears in-memory logins and deletes the
    /// Keychain entry. The synced item is removed from iCloud Keychain, so this
    /// affects every device on the same iCloud account. Also drops any legacy
    /// device-only copy. Used by the security reset.
    func disconnectAll() {
        connectedLogins.removeAll()
        _ = KeychainHelper.delete(forKey: keychainKey, synchronizable: true)
        _ = KeychainHelper.delete(forKey: keychainKey) // legacy device-only copy, if any
    }

    // MARK: API calls (via proxy)

    private func request(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> Data {
        guard let url = URL(string: FlinksConfig.proxyBaseURL + path) else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(FlinksConfig.apiKey, forHTTPHeaderField: "X-API-Key")
        if let body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            flinksLog.error("Flinks proxy error on \(path, privacy: .public)")
            throw URLError(.badServerResponse)
        }
        return data
    }

    /// Step 2 — exchange a LoginId for a RequestId.
    func authorize(loginId: String) async throws -> String {
        let data = try await request("/flinks/authorize", method: "POST",
                                     body: ["loginId": loginId, "mostRecentCached": true])
        let decoded = try JSONDecoder().decode(FlinksAuthorizeResponse.self, from: data)
        return decoded.requestId
    }

    /// Step 3 — fetch accounts + transactions for a RequestId.
    func getAccountsDetail(requestId: String) async throws -> FlinksAccountsResponse {
        let data = try await request("/flinks/accounts/\(requestId)")
        return try JSONDecoder().decode(FlinksAccountsResponse.self, from: data)
    }
}
