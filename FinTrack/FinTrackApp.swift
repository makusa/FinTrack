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
        // SwiftData performs lightweight migration automatically when
        // optional properties with default values are added to models.
        // No VersionedSchema needed for these changes.
        let schema = Schema([
            Account.self, Transaction.self, Category.self,
            RecurringTransaction.self, Loan.self, SavingsProject.self,
            CreditLine.self, CreditLineEntry.self,
            LoanPrepayment.self, Budget.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        let modelContainer: ModelContainer

        do {
            modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("FinTrack: ModelContainer init failed — \(error)")
        }

        container = modelContainer

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
