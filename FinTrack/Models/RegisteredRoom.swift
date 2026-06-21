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

    /// Federal RRSP annual dollar maximum (CAD): the per-year ceiling on NEW room
    /// from 18% of earned income. Used ONLY as a projection guardrail so a user's
    /// annual estimate can't inflate room past the legal max. NOT a tax figure.
    /// SOURCE OF TRUTH — confirm against CRA; append new years.
    static let reerAnnualMaxByYear: [Int: Decimal] = [
        2009: 21_000, 2010: 22_000, 2011: 22_450, 2012: 22_970,
        2013: 23_820, 2014: 24_270, 2015: 24_930, 2016: 25_370,
        2017: 26_010, 2018: 26_230, 2019: 26_500, 2020: 27_230,
        2021: 27_830, 2022: 29_210, 2023: 30_780, 2024: 31_560,
        2025: 32_490, 2026: 33_810,
    ]

    /// RRSP max for a year, clamped to the nearest known year outside the table
    /// so the guardrail always bounds (slightly stale is fine — it's a cap).
    static func reerAnnualMax(forYear year: Int) -> Decimal {
        if let v = reerAnnualMaxByYear[year] { return v }
        let years = reerAnnualMaxByYear.keys.sorted()
        guard let first = years.first, let last = years.last else { return 0 }
        if year < first { return reerAnnualMaxByYear[first]! }
        if year > last  { return reerAnnualMaxByYear[last]! }
        return reerAnnualMaxByYear[years.last { $0 <= year } ?? last]!
    }

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
        reerAnnualRoom: Decimal = 0,
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
            case .celi:
                // Keep remaining room, add new entitlement, restore this year's withdrawals.
                room = room + nextAnnual + withdrawalsThisYear
            case .reer:
                // Income-based: add the user's estimated annual new room (0 if unknown),
                // clamped to that year's federal RRSP maximum so an over-stated estimate
                // can't inflate room past the legal ceiling. Withdrawals don't restore room.
                room = room + min(reerAnnualRoom, RegisteredLimits.reerAnnualMax(forYear: y + 1))
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
        reerAnnualRoom: Decimal = 0,
        existingEntries: [RegisteredEntryData],
        newContribution amount: Decimal,
        on date: Date
    ) -> (over: Bool, excess: Decimal, roomBefore: Decimal) {
        let before = availableRoom(
            type: type, anchorYear: anchorYear, anchorAmount: anchorAmount,
            lifetimeContributedAtAnchor: lifetimeContributedAtAnchor,
            reerAnnualRoom: reerAnnualRoom,
            entries: existingEntries, asOf: date
        ).availableRoom
        // RRSP allows a $2,000 lifetime over-contribution cushion before penalty.
        let rawExcess = amount - before
        let cushion: Decimal = (type == .reer) ? 2_000 : 0
        let penaltyExcess = rawExcess - cushion
        return (penaltyExcess > 0, max(0, penaltyExcess), before)
    }

    /// Estimated penalty for one month on an over-contribution: 1% of the excess.
    static func estimatedMonthlyPenalty(excess: Decimal) -> Decimal {
        excess / 100
    }
}
