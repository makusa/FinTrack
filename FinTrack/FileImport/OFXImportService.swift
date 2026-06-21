//
//  OFXImportService.swift
//  FinTrack
//
//  App-facing glue for OFX/QFX import: account suggestion + commit through the
//  shared reconciliation pipeline, then remember the account mapping.
//

import Foundation
import SwiftData

enum OFXImportService {

    /// Suggest the destination account for a parsed statement.
    static func suggestAccount(for statement: OFXStatement,
                               among accounts: [Account]) -> AccountSuggestion {
        let descriptors = accounts.map {
            ImportAccountDescriptor(uuid: $0.uuid, currency: $0.currency, typeRaw: $0.typeRaw)
        }
        return OFXAccountMatcher.suggest(statement: statement,
                                         accounts: descriptors,
                                         remembered: ImportAccountMap.remembered())
    }

    /// Map the (already user-confirmed) statement onto the chosen account and run
    /// it through TransactionReconciler. Records the account mapping on success.
    @discardableResult
    static func commit(statement: OFXStatement,
                       into account: Account,
                       context: ModelContext) -> TransactionReconciler.Outcome {
        let rows = OFXImportMapper.map(statement: statement, accountUuid: account.uuid)
        let outcome = TransactionReconciler.reconcile(rows, context: context)
        ImportAccountMap.record(
            fingerprint: ImportAccountMap.fingerprint(bankId: statement.bankId, acctId: statement.accountId),
            accountUuid: account.uuid
        )
        return outcome
    }
}
