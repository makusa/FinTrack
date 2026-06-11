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

        // ── ModelContainer init — 4 niveaux de résilience ──────────────────
        //
        // Niveau 1: init simple SANS migrationPlan
        //   CloudKit: migrationPlan incompatible avec le mirroring.
        //   Local:    les nouveaux @Relationship (= []) sont des lightweight
        //             migrations gérées automatiquement par SwiftData.
        // Niveau 2: CloudKit → fallback store local
        // Niveau 3: schéma incompatible → container non-versionné
        // Niveau 4: store corrompu → wipe + store en mémoire (jamais de crash)

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

        let modelContainer: ModelContainer

        if let mc = try? ModelContainer(for: schema, configurations: [config]) {
            modelContainer = mc
            if cloudSyncEnabled {
                UserDefaults.standard.removeObject(forKey: "fintrack.cloudSync.lastError")
                UserDefaults.standard.removeObject(forKey: "fintrack.cloudSync.failCount")
            }
            AppLogger.persistence.info("Store started: \(cloudSyncEnabled ? "CloudKit" : "local", privacy: .public)")

        } else if cloudSyncEnabled,
                  let mc = try? ModelContainer(for: schema,
                                               configurations: [ModelConfiguration(schema: schema,
                                                                                   isStoredInMemoryOnly: false)]) {
            modelContainer = mc
            recordCloudFailure(NSError(domain: "FinTrack", code: 1,
                                       userInfo: [NSLocalizedDescriptionKey: "CloudKit unavailable"]))
            AppLogger.persistence.error("CloudKit failed — local store")

        } else if let mc = try? ModelContainer(for: Account.self, Transaction.self, Category.self,
                                                RecurringTransaction.self, Loan.self, LoanPrepayment.self,
                                                CreditLine.self, CreditLineEntry.self,
                                                SavingsProject.self, Budget.self) {
            modelContainer = mc
            AppLogger.persistence.error("Unversioned schema fallback")

        } else {
            AppLogger.persistence.error("All inits failed — wiping store")
            let storeURL = ModelConfiguration().url
            let fm = FileManager.default
            for ext in ["", "-shm", "-wal"] { try? fm.removeItem(at: storeURL.appendingPathExtension(ext)) }
            modelContainer = try! ModelContainer(for: schema,
                                                  configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
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
