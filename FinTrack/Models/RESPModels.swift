//
//  RESPModels.swift
//  FinTrack
//
//  SwiftData persistence for REEE/RESP accounts. The grant MATH lives in
//  RESPGrant.swift; these types only store data and bridge to it.
//
//  Option A (v1): one RESP account == one beneficiary (1:1 profile on Account,
//  mirroring CreditCardProfile / RegisteredAccountProfile). The $50,000 / $7,200 /
//  $3,600 caps are per beneficiary; under Option A that equals per account. A
//  shared-beneficiary aggregation (same child across multiple plans) can be added
//  later via a beneficiary key, as the registered service already does per type.
//
//  RESPContribution logs grant-eligible CONTRIBUTIONS only. Withdrawals (EAP /
//  refund of contributions, with their grant-repayment rules) are decumulation and
//  out of v1 scope; an account's cash balance is tracked via normal Transactions.
//

import Foundation
import SwiftData

// MARK: - Per-account profile (1:1 with Account) — the beneficiary

@Model
final class RESPProfile {
    var beneficiaryName: String = ""
    var birthYear: Int = Calendar.current.component(.year, from: .now)
    /// Drives IQEE eligibility (Québec provincial grant).
    var quebecResident: Bool = true
    var createdAt: Date = Date.now

    // 1:1 link; inverse + cascade declared on Account.respProfile.
    var account: Account?

    init(beneficiaryName: String, birthYear: Int, quebecResident: Bool = true) {
        self.beneficiaryName = beneficiaryName
        self.birthYear = birthYear
        self.quebecResident = quebecResident
        self.createdAt = .now
    }
}

// MARK: - Grant-eligible contribution

@Model
final class RESPContribution {
    var amount: Decimal = 0   // always positive
    var date: Date = Date.now
    var note: String = ""
    var createdAt: Date = Date.now

    /// Links the cash transfer (Transaction.transferPairId) this entry created,
    /// if the user also moved the money. nil = grant-tracking-only entry.
    var transferPairId: UUID? = nil

    // inverse + cascade declared on Account.respContributions.
    var account: Account?

    /// Plain value for the pure RESPGrantCalculator.
    var asData: RESPContributionData {
        RESPContributionData(date: date, amount: amount)
    }

    init(amount: Decimal, date: Date = .now, note: String = "") {
        self.amount = amount
        self.date = date
        self.note = note
        self.createdAt = .now
    }
}

// MARK: - Service (bridges @Model data to the pure calculator)

enum RESPGrantService {
    /// Grant + contribution status for a single RESP account (Option A: 1:1 with a
    /// beneficiary). Returns nil when the account isn't tagged as a RESP.
    static func evaluate(account: Account, asOf: Date = .now) -> RESPResult? {
        guard let profile = account.respProfile else { return nil }
        return RESPGrantCalculator.evaluate(
            birthYear: profile.birthYear,
            quebecResident: profile.quebecResident,
            contributions: (account.respContributions ?? []).map { $0.asData },
            asOf: asOf
        )
    }
}
