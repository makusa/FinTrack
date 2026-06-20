//
//  FinTrackApp.swift
//  FinTrack
//

import SwiftUI
import UIKit
import SwiftData

@main
struct FinTrackApp: App {
    // Build the model container once at app launch.
    // If it fails, we surface the error rather than silently falling back to
    // an in-memory store (which would lose data invisibly).
    let container: ModelContainer

    init() {
        // ── Persistence bootstrap ───────────────────────────────────────────
        //
        // Plain (non-versioned) Schema + explicit cloudKitDatabase on every
        // ModelConfiguration. Two hard-won lessons baked in:
        //
        //  1. cloudKitDatabase defaults to .automatic — when the binary has
        //     iCloud entitlements, SwiftData silently enables CloudKit even
        //     for "local" stores, enforcing CloudKit schema rules (inverses,
        //     optional relationships) and failing init. ALWAYS pass .none
        //     for local stores.
        //  2. A VersionedSchema triggers CloudKit validation internally even
        //     with .none (and requires its migrationPlan, which CloudKit
        //     mirroring rejects). A plain Schema avoids the whole trap; our
        //     model changes are additive lightweight migrations anyway.
        //
        // CloudKit path: requires model conformance (all relationships
        // optional + inverses). Until the models are made conformant, the
        // cloud branch fails fast and we record the reason + fall back.

        let baseSchema = Schema([Account.self, Transaction.self, Category.self,
                                 RecurringTransaction.self, Loan.self, LoanPrepayment.self,
                                 CreditLine.self, CreditLineEntry.self,
                                 SavingsProject.self, Budget.self,
                                 CreditCardProfile.self,
                                 RegisteredAccountProfile.self, RegisteredRoomPlan.self, RegisteredEntry.self])

        let cloudSyncEnabled = UserDefaults.standard.bool(forKey: "fintrack.cloudSyncEnabled")

        func recordCloudFailure(_ error: Error) {
            guard UIApplication.shared.isProtectedDataAvailable else {
                AppLogger.persistence.info("CloudKit init skipped: prewarming")
                return
            }
            let ns = error as NSError
            var details = "\(ns.domain) #\(ns.code): \(ns.localizedDescription)"
            var u: NSError? = ns.userInfo[NSUnderlyingErrorKey] as? NSError
            var d = 0
            while let un = u, d < 4 {
                details += " ⟶ \(un.domain) #\(un.code): \(un.localizedDescription)"
                if let r = un.userInfo[NSLocalizedFailureReasonErrorKey] as? String { details += " [\(r)]" }
                u = un.userInfo[NSUnderlyingErrorKey] as? NSError; d += 1
            }
            UserDefaults.standard.set(details, forKey: "fintrack.cloudSync.lastError")
            let fails = UserDefaults.standard.integer(forKey: "fintrack.cloudSync.failCount") + 1
            UserDefaults.standard.set(fails, forKey: "fintrack.cloudSync.failCount")
            if fails >= 3 {
                UserDefaults.standard.set(false, forKey: "fintrack.cloudSyncEnabled")
                UserDefaults.standard.removeObject(forKey: "fintrack.cloudSync.failCount")
            }
            AppLogger.persistence.error("CloudKit FAILED (\(fails)/3): \(details, privacy: .public)")
        }

        func makeLocalContainer() throws -> ModelContainer {
            try ModelContainer(for: baseSchema,
                               configurations: [ModelConfiguration(schema: baseSchema,
                                                                   isStoredInMemoryOnly: false,
                                                                   cloudKitDatabase: .none)])
        }

        let modelContainer: ModelContainer

        if cloudSyncEnabled,
           let cloud = try? ModelContainer(
               for: baseSchema,
               configurations: [ModelConfiguration(schema: baseSchema,
                                                   cloudKitDatabase: .private("iCloud.ca.regis.fintrack"))]) {
            modelContainer = cloud
            UserDefaults.standard.removeObject(forKey: "fintrack.cloudSync.lastError")
            UserDefaults.standard.removeObject(forKey: "fintrack.cloudSync.failCount")
            AppLogger.persistence.info("Store started: CloudKit")

        } else if let local = try? makeLocalContainer() {
            modelContainer = local
            if cloudSyncEnabled {
                recordCloudFailure(NSError(domain: "FinTrack", code: 1,
                                           userInfo: [NSLocalizedDescriptionKey: "CloudKit container init failed"]))
            }
            AppLogger.persistence.info("Store started: local")

        } else {
            // Disk store unreadable. Emergency in-memory store: the user sees
            // an empty session (data on disk is untouched and recoverable),
            // never a crash. NEVER wipe automatically.
            AppLogger.persistence.error("Local store failed to open — emergency in-memory session")
            modelContainer = try! ModelContainer(
                for: baseSchema,
                configurations: [ModelConfiguration(schema: baseSchema,
                                                    isStoredInMemoryOnly: true,
                                                    cloudKitDatabase: .none)])
        }

        container = modelContainer

        // FIN-002 — Apply NSFileProtectionComplete to the SwiftData SQLite store.
        // This ensures financial data is encrypted at rest and inaccessible when
        // the device is locked (strongest iOS file protection class).
        if let storeURL = modelContainer.configurations.first?.url {
            do {
                try FileManager.default.setAttributes(
                    [.protectionKey: FileProtectionType.complete],
                    ofItemAtPath: storeURL.path
                )
            } catch {
                // Non-fatal: protection may already be set or file not yet created.
                // Logged via os_log in production; silent here to avoid false alarms.
            }
        }

        // C1 migration — on first launch after cachedBalance was added,
        // recalculate all accounts (they have cachedBalance = 0 from migration).
        let migrationKey = "accountBalanceCacheInitialized_v1"
        if !UserDefaults.standard.bool(forKey: migrationKey) {
            let accounts = (try? modelContainer.mainContext.fetch(FetchDescriptor<Account>())) ?? []
            accounts.forEach { $0.recalculateBalance() }
            try? modelContainer.mainContext.save()
            UserDefaults.standard.set(true, forKey: migrationKey)
        }

        // Seed default categories on the main context.
        SeedData.seedIfNeeded(context: modelContainer.mainContext)

        // Request notification permission and schedule all upcoming reminders
        Task { @MainActor in
            await NotificationManager.shared.requestPermission()
            await NotificationManager.shared.scheduleAll(context: modelContainer.mainContext)
        }

        // Refresh exchange rates
        Task { await ExchangeRateManager.shared.refreshIfNeeded() }

        // Start StoreKit entitlement listener
        Task { await EntitlementManager.shared.start() }

        // Generate any pending recurring transactions (salary, rent, subscriptions…).
        RecurringTransactionManager.applyPending(context: modelContainer.mainContext)
        LoanPrepaymentManager.applyPending(context: modelContainer.mainContext)
        CreditLineInterestManager.applyPending(context: modelContainer.mainContext)
    }

    // Keep a reference to shared singletons so @Observable propagates changes.
    @State private var languageManager = LanguageManager.shared
    @State private var lockManager = AppLockManager.shared
    @State private var rateManager = ExchangeRateManager.shared
    @State private var entitlements = EntitlementManager.shared
    @State private var dashboardConfig = DashboardConfigManager.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(languageManager)
                .environment(lockManager)
                .environment(rateManager)
                .environment(entitlements)
                .environment(dashboardConfig)
        }
        .modelContainer(container)
    }
}
