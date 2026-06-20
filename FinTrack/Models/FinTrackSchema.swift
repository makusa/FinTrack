//
//  FinTrackSchema.swift
//  FinTrack
//
//  Versioned schema + migration plan. Required before enabling CloudKit:
//  every future model change must go through a new SchemaV(n) and a
//  migration stage here, so existing stores (local and cloud) migrate
//  predictably instead of crashing at launch.
//

import Foundation
import SwiftData

// MARK: - V1 — current schema (all 14 models)

enum FinTrackSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Account.self,
         Transaction.self,
         Category.self,
         RecurringTransaction.self,
         Loan.self,
         LoanPrepayment.self,
         CreditLine.self,
         CreditLineEntry.self,
         SavingsProject.self,
         Budget.self,
         CreditCardProfile.self,
         RegisteredAccountProfile.self,
         RegisteredRoomPlan.self,
         RegisteredEntry.self]
    }
}

// MARK: - Migration plan

enum FinTrackMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [FinTrackSchemaV1.self]
        // Future versions append here, e.g.:
        // [FinTrackSchemaV1.self, FinTrackSchemaV2.self]
    }

    static var stages: [MigrationStage] {
        []
        // Future migrations append here, e.g.:
        // [migrateV1toV2]
    }
}
