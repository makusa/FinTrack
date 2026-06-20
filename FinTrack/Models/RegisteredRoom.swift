//
//  RegisteredRoom.swift
//  FinTrack
//
//  Pure, dependency-free engine for registered-account contribution room
//  (CELI/TFSA and CELIAPP/FHSA). No SwiftData, no UI — so it is unit-testable
//  in isolation (compile with swiftc + a harness).
//
//  Design: ANCHOR-based. The user supplies their CRA contribution room as of
//  January 1 of an anchor year; the engine projects forward applying each
//  type's rules. Room is PER PERSON PER TYPE, aggregated across all accounts
//  of that type — the caller passes a flat list of entries.
//
//  Key Canadian rules encoded here:
//   • CELI withdrawals restore room on Jan 1 of the FOLLOWING year (not same year).
//   • CELIAPP withdrawals never restore room; $40,000 lifetime cap; unused room
//     carries forward only up to $8,000/yr.
//   • Over-contribution penalty: 1% per month on the excess.
//

import Foundation

// MARK: - Registered type (pure; localized label lives in the app layer)

enum RegisteredType: String, CaseIterable, Identifiable {
    case celi      // TFSA
    case celiapp   // FHSA
    case reer      // RRSP — income-based; room calc not implemented here yet

    var id: String { rawValue }

    /// Does an eligible withdrawal restore contribution room (next Jan 1)?
    var restoresRoomOnWithdrawal: Bool {
        switch self {
        case .celi:              return true
        case .celiapp, .reer:    return false
        }
    }

    /// Lifetime contribution cap, if any.
    var lifetimeCap: Decimal? {
        switch self {
        case .celiapp: return 40_000
        case .celi, .reer: return nil
        }
    }

    /// Max unused room carried forward to the next year (nil = unlimited accrual).
    var maxCarryforwardPerYear: Decimal? {
        switch self {
        case .celiapp: return 8_000
        case .celi, .reer: return nil
        }
    }
}

// MARK: - Annual limits (SOURCE OF TRUTH — confirmed against CRA; append new years)

enum RegisteredLimits {
    /// CELI/TFSA annual dollar limits (CAD). Confirmed: 2024–2026 = 7,000.
    static let celiAnnual: [Int: Decimal] = [
        2009: 5_000, 2010: 5_000, 2011: 5_000, 2012: 5_000,
        2013: 5_500, 2014: 5_500,
        2015: 10_000,
        2016: 5_500, 2017: 5_500, 2018: 5_500,
        2019: 6_000, 2020: 6_000, 2021: 6_000, 2022: 6_000,
        2023: 6_500,
        2024: 7_000, 2025: 7_000, 2026: 7_000,
    ]

    /// Annual entitlement for a given type and year.
    static func annualLimit(_ type: RegisteredType, year: Int) -> Decimal {
        switch type {
        case .celi:    return celiAnnual[year] ?? 0
        case .celiapp: return year >= 2023 ? 8_000 : 0   // FHSA launched 2023
        case .reer:    return 0                          // income-based; handled elsewhere
        }
    }
}

// MARK: - Plain inputs/outputs

/// A contribution or withdrawal, decoupled from any @Model.
struct RegisteredEntryData {
    let date: Date
    let amount: Decimal        // always positive
    let isContribution: Bool   // false = withdrawal
}

struct RoomResult {
    let availableRoom: Decimal      // negative => over-contributed by |availableRoom|
    let lifetimeContributed: Decimal
    var isOverContributed: Bool { availableRoom < 0 }
    var excess: Decimal { availableRoom < 0 ? -availableRoom : 0 }
}

// MARK: - Calculator (pure)

enum RegisteredRoomCalculator {

    private static func year(_ date: Date) -> Int {
        Calendar.current.component(.year, from: date)
    }

    /// Available contribution room for `type` as of `asOf`, given the anchor and
    /// the full set of entries across all accounts of that type.
    static func availableRoom(
        type: RegisteredType,
        anchorYear: Int,
        anchorAmount: Decimal,
        lifetimeContributedAtAnchor: Decimal = 0,
        entries: [RegisteredEntryData],
        asOf: Date = .now
    ) -> RoomResult {
        let currentYear = year(asOf)
        var room = anchorAmount
        var lifetime = lifetimeContributedAtAnchor

        guard currentYear >= anchorYear else {
            return RoomResult(availableRoom: room, lifetimeContributed: lifetime)
        }

        let relevant = entries
            .filter { $0.date <= asOf && year($0.date) >= anchorYear }
            .sorted { $0.date < $1.date }

        for y in anchorYear...currentYear {
            let yearEntries = relevant.filter { year($0.date) == y }
            var withdrawalsThisYear: Decimal = 0
            for e in yearEntries {
                if e.isContribution {
                    room -= e.amount
                    lifetime += e.amount
                } else {
                    withdrawalsThisYear += e.amount   // effect deferred (or none)
                }
            }

            guard y < currentYear else { break }

            let nextAnnual = RegisteredLimits.annualLimit(type, year: y + 1)
            switch type {
            case .celi, .reer:
                // Keep remaining room, add new entitlement, restore this year's withdrawals.
                room = room + nextAnnual + withdrawalsThisYear
            case .celiapp:
                // No restoration. Unused room carries forward capped at maxCarryforward.
                let cap = type.maxCarryforwardPerYear ?? room
                let carry = min(max(0, room), cap)
                room = carry + nextAnnual
            }

            if let lifeCap = type.lifetimeCap {
                room = min(room, max(0, lifeCap - lifetime))
            }
        }

        if let lifeCap = type.lifetimeCap {
            room = min(room, max(0, lifeCap - lifetime))
        }

        return RoomResult(availableRoom: room, lifetimeContributed: lifetime)
    }

    /// Would contributing `amount` on `date` push the holder over their room?
    /// Returns the excess (0 if fine) and the room available just before it.
    static func overContributionCheck(
        type: RegisteredType,
        anchorYear: Int,
        anchorAmount: Decimal,
        lifetimeContributedAtAnchor: Decimal = 0,
        existingEntries: [RegisteredEntryData],
        newContribution amount: Decimal,
        on date: Date
    ) -> (over: Bool, excess: Decimal, roomBefore: Decimal) {
        let before = availableRoom(
            type: type, anchorYear: anchorYear, anchorAmount: anchorAmount,
            lifetimeContributedAtAnchor: lifetimeContributedAtAnchor,
            entries: existingEntries, asOf: date
        ).availableRoom
        let excess = amount - before
        return (excess > 0, max(0, excess), before)
    }

    /// Estimated penalty for one month on an over-contribution: 1% of the excess.
    static func estimatedMonthlyPenalty(excess: Decimal) -> Decimal {
        excess / 100
    }
}
