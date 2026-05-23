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
                             CreditLine.self, CreditLineEntry.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("FinTrack: ModelContainer init failed — \(error)")
        }

        // Seed default categories on the main context.
        SeedData.seedIfNeeded(context: container.mainContext)

        // Generate any pending recurring transactions (salary, rent, subscriptions…).
        RecurringTransactionManager.applyPending(context: container.mainContext)
        CreditLineInterestManager.applyPending(context: container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
