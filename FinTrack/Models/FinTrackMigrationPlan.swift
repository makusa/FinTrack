//
//  FinTrackMigrationPlan.swift
//  FinTrack
//
//  SwiftData versioned schema + migration plan.
//  Each time a model property is added/removed/renamed, a new
//  VersionedSchema is defined and a MigrationStage is added.
//
//  Current versions:
//    V1 — initial schema (all models without bankDomain)
//    V2 — adds Account.bankDomain: String?
//

import SwiftData
import Foundation

// MARK: - V1 (original schema)

enum FinTrackSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Account.self, Transaction.self, Category.self,
         RecurringTransaction.self, Loan.self, SavingsProject.self,
         CreditLine.self, CreditLineEntry.self,
         LoanPrepayment.self, Budget.self]
    }
}

// MARK: - V2 (adds Account.bankDomain)

enum FinTrackSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Account.self, Transaction.self, Category.self,
         RecurringTransaction.self, Loan.self, SavingsProject.self,
         CreditLine.self, CreditLineEntry.self,
         LoanPrepayment.self, Budget.self]
    }
}

// MARK: - Migration plan

enum FinTrackMigrationPlan: SchemaMigrationPlan {

    static var schemas: [any VersionedSchema.Type] {
        [FinTrackSchemaV1.self, FinTrackSchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2]
    }

    /// V1 → V2: Account gains bankDomain (optional String, defaults to nil).
    /// SwiftData lightweight migration handles this automatically — no
    /// custom closure needed since the new property has a default value.
    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: FinTrackSchemaV1.self,
        toVersion:   FinTrackSchemaV2.self
    )
}
