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
        let schema = Schema([Account.self, Transaction.self, Category.self,
                             RecurringTransaction.self, Loan.self, SavingsProject.self,
                             CreditLine.self, CreditLineEntry.self,
                             LoanPrepayment.self,
                             Budget.self])
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

        // Generate any pending recurring transactions (salary, rent, subscriptions…).
        RecurringTransactionManager.applyPending(context: modelContainer.mainContext)
        CreditLineInterestManager.applyPending(context: modelContainer.mainContext)
    }

    // Keep a reference to shared singletons so @Observable propagates changes.
    @State private var languageManager = LanguageManager.shared
    @State private var lockManager = AppLockManager.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(languageManager)
                .environment(lockManager)
        }
        .modelContainer(container)
    }
}
