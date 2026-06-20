//
//  TransactionMatcher.swift
//  FinTrack
//
//  Pure matching logic for Option C reconciliation: deciding whether an
//  incoming bank (synced) transaction duplicates a transaction the user
//  already entered manually.
//
//  Foundation-only and free of SwiftData/UI so it can be unit-tested in
//  isolation. The SwiftData layer maps @Model rows to MatchCandidate and
//  acts on the returned decision.
//

import Foundation

/// A manual transaction that a synced row could duplicate. Only manual,
/// not-yet-reconciled rows (externalId == nil) should be passed as candidates.
struct MatchCandidate: Equatable {
    let id: String          // opaque identity supplied by the caller
    let accountKey: String  // stable account identity (both sides must share it)
    let isIncome: Bool
    let amount: Decimal
    let date: Date
}

/// Outcome of matching one incoming synced transaction against the candidates.
enum TransactionMatchDecision: Equatable {
    case insertNew                          // no manual match — create the synced row as usual
    case autoLink(candidateId: String)      // exactly one high-confidence match — adopt it
    case review(candidateIds: [String])     // 2+ plausible matches — flag for user review
}

enum TransactionMatcher {

    /// Slack (in calendar days) allowed between the manual entry date and the
    /// bank posting date. Manual = purchase date; bank = posting date, which
    /// can lag a few days.
    static let dateWindowDays = 4

    /// Amounts are currency (cents). Compare with a half-cent epsilon so float
    /// artifacts from Decimal(Double) (Flinks amounts arrive as Double) never
    /// cause a real match to be missed, while genuinely different cent amounts
    /// (>= 0.01 apart) never match.
    static let amountEpsilon = Decimal(string: "0.005")!

    /// Decide what to do with one incoming synced transaction.
    static func decide(
        incomingAccountKey: String,
        incomingIsIncome: Bool,
        incomingAmount: Decimal,
        incomingDate: Date,
        candidates: [MatchCandidate],
        windowDays: Int = dateWindowDays,
        epsilon: Decimal = amountEpsilon,
        calendar: Calendar = .current
    ) -> TransactionMatchDecision {
        let matches = candidates.filter { c in
            c.accountKey == incomingAccountKey
                && c.isIncome == incomingIsIncome
                && amountsMatch(c.amount, incomingAmount, epsilon: epsilon)
                && withinWindow(c.date, incomingDate, days: windowDays, calendar: calendar)
        }

        switch matches.count {
        case 0:
            return .insertNew
        case 1:
            return .autoLink(candidateId: matches[0].id)
        default:
            // Ambiguous — order by date proximity for a stable, useful review list.
            let ordered = matches.sorted {
                abs($0.date.timeIntervalSince(incomingDate)) < abs($1.date.timeIntervalSince(incomingDate))
            }
            return .review(candidateIds: ordered.map(\.id))
        }
    }

    static func amountsMatch(_ a: Decimal, _ b: Decimal, epsilon: Decimal) -> Bool {
        abs(a - b) < epsilon
    }

    static func withinWindow(_ a: Date, _ b: Date, days: Int, calendar: Calendar) -> Bool {
        let lo = calendar.startOfDay(for: min(a, b))
        let hi = calendar.startOfDay(for: max(a, b))
        let diff = calendar.dateComponents([.day], from: lo, to: hi).day ?? Int.max
        return diff <= days
    }
}
