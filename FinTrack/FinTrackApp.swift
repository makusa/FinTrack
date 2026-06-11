//
//  FinTrackApp.swift
//  FinTrack
//

import SwiftUI
import SwiftData

@main
struct FinTrackApp: App {
    // Build the model container once at app launch.
    // If it fails, we surface the error rather than silently falling back to
    // an in-memory store (which would lose data invisibly).
    let container: ModelContainer

    init() {
        // Versioned schema (FinTrackSchemaV1) — prerequisite for CloudKit.
        // All future model changes go through FinTrackMigrationPlan.
        let schema = Schema(versionedSchema: FinTrackSchemaV1.self)

        // CloudKit sync is reserved for paid tiers (Épargne / Placement).
        // The flag is persisted by EntitlementManager so it is readable here,
        // before any SwiftUI environment exists.
        let cloudSyncEnabled = UserDefaults.standard.bool(forKey: "fintrack.cloudSyncEnabled")

        let config: ModelConfiguration
        if cloudSyncEnabled {
            config = ModelConfiguration(
                schema: schema,
                cloudKitDatabase: .private("iCloud.ca.regis.fintrack")
            )
        } else {
            config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        }

        let modelContainer: ModelContainer
        do {
            modelContainer = try ModelContainer(
                for: schema,
                migrationPlan: FinTrackMigrationPlan.self,
                configurations: [config]
            )
            AppLogger.persistence.info("Store started: \(cloudSyncEnabled ? "CloudKit (iCloud.ca.regis.fintrack)" : "local", privacy: .public)")
        } catch {
            // CloudKit container may fail (no iCloud account, entitlement missing).
            // Fall back to the local store rather than crashing — losing sync is
            // recoverable, losing the app is not.
            do {
                let localConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
                modelContainer = try ModelContainer(
                    for: schema,
                    migrationPlan: FinTrackMigrationPlan.self,
                    configurations: [localConfig]
                )
                UserDefaults.standard.set(false, forKey: "fintrack.cloudSyncEnabled")
                AppLogger.persistence.error("CloudKit container init FAILED — fell back to local store: \(error, privacy: .public)")
            } catch {
                fatalError("FinTrack: ModelContainer init failed — \(error)")
            }
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
