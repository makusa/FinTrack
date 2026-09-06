//
//  BankSyncProvider.swift
//  FinTrack
//
//  Single place to choose the active bank-sync provider before going
//  to production. Both Plaid and Flinks are fully implemented; switch
//  activeProvider when you've decided which one to ship.
//
//  Plaid:  self-serve sandbox at dashboard.plaid.com
//  Flinks: requires a private instance (contact flinks.com/contact)
//          or use the public Toolbox (toolbox-iframe.private.fin.ag)
//

import SwiftUI
import SwiftData

// MARK: - Provider selection (change before release)

enum BankSyncProviderChoice {
    case plaid
    case flinks
}

/// Flip this constant to switch providers. No other code needs to change.
let activeBankSyncProvider: BankSyncProviderChoice = .plaid

// MARK: - Unified entry point used by SettingsView

/// Returns the correct connection view for the active provider.
struct BankSyncDestinationView: View {
    var body: some View {
        switch activeBankSyncProvider {
        case .plaid:  ConnectedAccountsView()
        case .flinks: BankSyncView()
        }
    }
}

/// Label shown in Réglages for the active provider.
var bankSyncProviderLabel: String {
    switch activeBankSyncProvider {
    case .plaid:  "Connexion bancaire"
    case .flinks: "Connexion bancaire"
    }
}

// MARK: - Provider-agnostic operations

/// Purges bank connections for BOTH providers (tokens + local metadata).
/// The security reset must clear everything regardless of which provider is
/// active, so flipping `activeBankSyncProvider` never leaves stale tokens
/// behind. Always call this rather than a specific provider's manager.
@MainActor
func disconnectAllBankProviders() {
    PlaidManager.shared.disconnectAll()
    FlinksManager.shared.disconnectAll()
}
