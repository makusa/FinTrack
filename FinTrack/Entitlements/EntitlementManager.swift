//
//  EntitlementManager.swift
//  FinTrack
//
//  Manages in-app purchases and subscriptions via StoreKit 2.
//
//  Products (configure in App Store Connect):
//    ca.regis.fintrack.pro           — Non-consumable, $19.99 CAD (one-time)
//    ca.regis.fintrack.plaid_monthly — Auto-renewable subscription, $3.99 CAD/month
//
//  Tier summary:
//    Free  — unlimited accounts (manual), unlimited transactions, max 5 recurring, max 2 loans, max 1 credit line, basic dashboard
//    Pro   — Everything: analytics, budgets, loans, recurring, transfers, FX, export…
//    Plaid — Automatic bank sync (requires active subscription)
//

import StoreKit
import SwiftUI

// MARK: - Product IDs

enum FinTrackProduct: String, CaseIterable {
    case pro         = "ca.regis.fintrack.pro"
    case plaidMonthly = "ca.regis.fintrack.plaid_monthly"

    var displayName: String {
        switch self {
        case .pro:          return LanguageManager.shared["entitlement.pro.name"]
        case .plaidMonthly: return LanguageManager.shared["entitlement.plaid.name"]
        }
    }

    var price: String {
        switch self {
        case .pro:          return "19,99 $"
        case .plaidMonthly: return "3,99 $/mois"
        }
    }

    var icon: String {
        switch self {
        case .pro:          return "star.fill"
        case .plaidMonthly: return "building.columns.badge.plus"
        }
    }
}

// MARK: - Tier

enum FinTrackTier: Equatable {
    case free
    case pro           // one-time purchase
    case plaid         // monthly subscription (implies pro)
}

// MARK: - Limits

enum FinTrackLimit {
    /// Maximum recurring transactions (active + paused) in the free tier.
    static let freeMaxRecurring = 5
    /// Maximum active loans in the free tier. Archived (paid-off) loans don't count.
    static let freeMaxLoans = 2
    /// Maximum active credit lines in the free tier. Archived lines don't count.
    static let freeMaxCreditLines = 1
}

// MARK: - EntitlementManager

@Observable
final class EntitlementManager {

    static let shared = EntitlementManager()
    private init() {}

    // MARK: State

    private(set) var hasPro:   Bool = false
    private(set) var hasPlaid: Bool = false
    private(set) var isLoading = false
    private(set) var products: [Product] = []
    private(set) var purchaseError: String? = nil

    var tier: FinTrackTier {
        if hasPlaid { return .plaid }
        if hasPro   { return .pro }
        return .free
    }

    // MARK: - Lifecycle

    func start() async {
        await loadProducts()
        await refreshEntitlements()
        // Transaction listener runs indefinitely — launch as independent Task
        // so it doesn't block start() from returning
        Task { await self.listenForTransactions() }
    }

    // MARK: - Products

    func loadProducts() async {
        do {
            let loaded = try await Product.products(for: FinTrackProduct.allCases.map { $0.rawValue })
            await MainActor.run {
                self.products = loaded.sorted { $0.price < $1.price }
            }
        } catch {
            print("EntitlementManager: product load failed — \(error)")
        }
    }

    func product(for id: FinTrackProduct) -> Product? {
        products.first { $0.id == id.rawValue }
    }

    // MARK: - Purchase

    @MainActor
    func purchase(_ productId: FinTrackProduct) async -> Bool {
        guard let product = product(for: productId) else {
            purchaseError = LanguageManager.shared["entitlement.error.unavailable"]
            return false
        }

        isLoading = true
        purchaseError = nil

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await updateEntitlements(for: transaction)
                await transaction.finish()
                isLoading = false
                return true

            case .userCancelled:
                isLoading = false
                return false

            case .pending:
                isLoading = false
                return false

            @unknown default:
                isLoading = false
                return false
            }
        } catch {
            purchaseError = error.localizedDescription
            isLoading = false
            return false
        }
    }

    // MARK: - Restore

    @MainActor
    func restore() async {
        isLoading = true
        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            purchaseError = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Entitlement refresh

    @MainActor
    func refreshEntitlements() async {
        var newHasPro   = false
        var newHasPlaid = false

        for await result in StoreKit.Transaction.currentEntitlements {
            if let transaction = try? checkVerified(result) {
                switch transaction.productID {
                case FinTrackProduct.pro.rawValue:
                    newHasPro = true
                case FinTrackProduct.plaidMonthly.rawValue:
                    newHasPlaid = true
                    newHasPro   = true  // Plaid implies Pro
                default:
                    break
                }
            }
        }

        hasPro   = newHasPro
        hasPlaid = newHasPlaid
    }

    // MARK: - Transaction listener

    private func listenForTransactions() async {
        for await result in StoreKit.Transaction.updates {
            if let transaction = try? checkVerified(result) {
                await updateEntitlements(for: transaction)
                await transaction.finish()
            }
        }
    }

    @MainActor
    private func updateEntitlements(for transaction: StoreKit.Transaction) async {
        switch transaction.productID {
        case FinTrackProduct.pro.rawValue:
            hasPro = transaction.revocationDate == nil
        case FinTrackProduct.plaidMonthly.rawValue:
            hasPlaid = transaction.revocationDate == nil
            if hasPlaid { hasPro = true }
        default:
            break
        }
    }

    // MARK: - Verification

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let value):
            return value
        }
    }

    // MARK: - Override (debug / promo)

    #if DEBUG
    @MainActor func simulatePro()   { hasPro = true }
    @MainActor func simulatePlaid() { hasPro = true; hasPlaid = true }
    @MainActor func simulateFree()  { hasPro = false; hasPlaid = false }
    #endif
}
