//
//  RESPGrant.swift
//  FinTrack
//
//  Pure, dependency-free engine for REEE/RESP education-savings GRANTS, PER
//  BENEFICIARY. No SwiftData, no UI — unit-testable with swiftc + a harness.
//
//  Unlike CELI/REER this is NOT a contribution-room model: there is no annual
//  contribution limit, only a $50,000 lifetime cap per beneficiary. The value is
//  the government grant earned by contributing, which the engine optimizes.
//
//  Models the CONTRIBUTION-DRIVEN grants only (deliberately NOT the income-tested
//  ones, to stay out of tax territory):
//   • Basic CESG/SCEE (federal): 20% of contributions; $2,500/yr of grant-eligible
//     contribution room accrues and carries forward; max $1,000 CESG in any year
//     (i.e. up to $5,000 contribution, using one year of carry-forward); $7,200
//     lifetime.
//   • Basic IQEE (Québec): 10%; $250/yr base, max $500/yr with carry-forward;
//     $3,600 lifetime.
//  Grant room accrues each year from max(birthYear, 2007) through the year the
//  beneficiary turns 17 (the CESG age ceiling). Contributions are tracked in full
//  (history is ≤17 years and sparse, so no anchor is needed — contrast CELI).
//
//  DEFERRED (income-tested / edge): Additional CESG, Canada Learning Bond, the
//  16–17 prior-contribution eligibility rule, pre-2007 rules, other provinces.
//

import Foundation

// MARK: - Programs

enum RESPGrantProgram {
    case cesg   // federal SCEE
    case iqee   // Québec

    /// Match rate applied to grant-eligible contributions.
    var matchRate: Decimal {
        switch self {
        case .cesg: return Decimal(string: "0.20")!
        case .iqee: return Decimal(string: "0.10")!
        }
    }

    /// Base grant earned per year on the first $2,500 (informational).
    var annualBaseMax: Decimal {
        switch self {
        case .cesg: return 500
        case .iqee: return 250
        }
    }

    /// Maximum grant payable in a single year, using up to one year of
    /// carried-forward room (both programs cap grant-eligible contribution at
    /// $5,000/yr: 1000/0.20 = 500/0.10 = 5000).
    var annualMaxWithCarryforward: Decimal {
        switch self {
        case .cesg: return 1_000
        case .iqee: return 500
        }
    }

    /// Lifetime grant ceiling per beneficiary.
    var lifetimeMax: Decimal {
        switch self {
        case .cesg: return 7_200
        case .iqee: return 3_600
        }
    }
}

// MARK: - Plain inputs/outputs

struct RESPContributionData {
    let date: Date
    let amount: Decimal   // always positive
}

struct RESPGrantResult {
    let program: RESPGrantProgram
    let earned: Decimal
    var remaining: Decimal { max(0, program.lifetimeMax - earned) }
    /// How many more dollars contributed THIS year would still attract grant.
    let roomDollarsThisYear: Decimal
}

struct RESPResult {
    // Contributions (toward the $50,000 lifetime cap)
    let totalContributed: Decimal
    let contributionRoomRemaining: Decimal     // 50,000 − total (may go negative)
    var isOverContributed: Bool { contributionExcess > 0 }
    let contributionExcess: Decimal

    // Grants
    let cesg: RESPGrantResult
    let iqee: RESPGrantResult                   // .earned == 0 when not a Québec resident

    /// Dollars to contribute THIS year to capture the maximum CESG still available
    /// (the same contribution also earns IQEE up to its own cap). Capped so it
    /// never exceeds the remaining $50,000 contribution room.
    let suggestedContributionThisYear: Decimal

    var isPastGrantAge: Bool { cesg.roomDollarsThisYear == 0 && suggestedContributionThisYear == 0 }
}

// MARK: - Calculator (pure)

enum RESPGrantCalculator {

    static let lifetimeContributionLimit: Decimal = 50_000
    /// Grant-eligible contribution room that accrues each beneficiary-year.
    static let grantRoomPerYear: Decimal = 2_500
    /// Modern CESG/IQEE rules (and the $2,500 room) date from 2007.
    static let grantStartYear = 2007
    /// CESG is available through the end of the year the beneficiary turns 17.
    static let grantAgeCeiling = 17

    private static func year(_ date: Date) -> Int {
        Calendar.current.component(.year, from: date)
    }

    static func evaluate(
        birthYear: Int,
        quebecResident: Bool,
        contributions: [RESPContributionData],
        asOf: Date = .now
    ) -> RESPResult {
        let currentYear = year(asOf)

        var byYear: [Int: Decimal] = [:]
        var total: Decimal = 0
        for c in contributions where c.date <= asOf {
            byYear[year(c.date), default: 0] += c.amount
            total += c.amount
        }

        let cesg = computeProgram(.cesg, birthYear: birthYear,
                                  contributionsByYear: byYear, currentYear: currentYear)
        let iqee = quebecResident
            ? computeProgram(.iqee, birthYear: birthYear,
                             contributionsByYear: byYear, currentYear: currentYear)
            : RESPGrantResult(program: .iqee, earned: 0, roomDollarsThisYear: 0)

        let roomRemaining = lifetimeContributionLimit - total
        let excess = total > lifetimeContributionLimit ? total - lifetimeContributionLimit : 0
        let suggested = max(0, min(cesg.roomDollarsThisYear, roomRemaining))

        return RESPResult(
            totalContributed: total,
            contributionRoomRemaining: roomRemaining,
            contributionExcess: excess,
            cesg: cesg,
            iqee: iqee,
            suggestedContributionThisYear: suggested
        )
    }

    /// 1%/month penalty on a $50,000 over-contribution (mirrors CRA/CELI/REER).
    static func estimatedMonthlyPenalty(excess: Decimal) -> Decimal { excess / 100 }

    // MARK: - Per-program engine

    private static func computeProgram(
        _ program: RESPGrantProgram,
        birthYear: Int,
        contributionsByYear: [Int: Decimal],
        currentYear: Int
    ) -> RESPGrantResult {
        let roomStartYear = max(birthYear, grantStartYear)
        let ageCeilingYear = birthYear + grantAgeCeiling
        let lastGrantYear = min(currentYear, ageCeilingYear)

        guard roomStartYear <= lastGrantYear else {
            return RESPGrantResult(program: program, earned: 0, roomDollarsThisYear: 0)
        }

        let maxAttractingPerYear = program.annualMaxWithCarryforward / program.matchRate  // $5,000
        var accumulatedRoom: Decimal = 0
        var earned: Decimal = 0
        var roomDollarsThisYear: Decimal = 0

        for y in roomStartYear...lastGrantYear {
            accumulatedRoom += grantRoomPerYear
            let contribY = contributionsByYear[y] ?? 0

            var attracting = min(min(contribY, accumulatedRoom), maxAttractingPerYear)
            var grantThisYear = program.matchRate * attracting
            if earned + grantThisYear > program.lifetimeMax {
                grantThisYear = max(0, program.lifetimeMax - earned)
                attracting = grantThisYear / program.matchRate
            }
            earned += grantThisYear
            accumulatedRoom -= attracting

            if y == currentYear {
                let perYearLeft = maxAttractingPerYear - attracting
                let lifetimeLeftDollars = (program.lifetimeMax - earned) / program.matchRate
                roomDollarsThisYear = max(0, min(min(accumulatedRoom, perYearLeft), lifetimeLeftDollars))
            }
        }

        return RESPGrantResult(program: program, earned: earned, roomDollarsThisYear: roomDollarsThisYear)
    }
}
