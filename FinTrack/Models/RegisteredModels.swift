//
//  RegisteredModels.swift
//  FinTrack
//
//  SwiftData persistence for registered accounts, plus the localized labels
//  for the (pure) RegisteredType. The contribution-room MATH lives in
//  RegisteredRoom.swift; these types only store data and bridge to it.
//
//  Two SwiftData models + a bridging service:
//   • RegisteredAccountProfile — 1:1 tag on an Account (this is a CELI/CELIAPP…).
//   • RegisteredRoomPlan       — the per-type anchor (room is per person per type).
//  Contributions/withdrawals are NOT a separate model: room is derived from each
//  account's Transactions (income = contribution, expense = withdrawal) by
//  RegisteredRoomService, which feeds the pure calculator in RegisteredRoom.swift.
//

import Foundation
import SwiftData

// MARK: - Localized labels for the pure RegisteredType (app layer)

extension RegisteredType {
    var label: String {
        switch self {
        case .celi:    return LanguageManager.shared["reg.type.celi"]
        case .celiapp: return LanguageManager.shared["reg.type.celiapp"]
        case .reer:    return LanguageManager.shared["reg.type.reer"]
        }
    }

    /// Acronym used in compact UI, identical across languages.
    var shortName: String {
        switch self {
        case .celi:    return "CELI"
        case .celiapp: return "CELIAPP"
        case .reer:    return "REER"
        }
    }
}

// MARK: - Per-account profile (1:1 with Account)

@Model
final class RegisteredAccountProfile {
    var registeredTypeRaw: String = RegisteredType.celi.rawValue
    var createdAt: Date = Date.now

    // 1:1 link; inverse + cascade declared on Account.registeredProfile.
    var account: Account?

    var registeredType: RegisteredType {
        get { RegisteredType(rawValue: registeredTypeRaw) ?? .celi }
        set { registeredTypeRaw = newValue.rawValue }
    }

    init(registeredType: RegisteredType) {
        self.registeredTypeRaw = registeredType.rawValue
        self.createdAt = .now
    }
}

// MARK: - Per-type room plan (the anchor; one per type, per person)

@Model
final class RegisteredRoomPlan {
    var registeredTypeRaw: String = RegisteredType.celi.rawValue
    var anchorYear: Int = Calendar.current.component(.year, from: .now)
    var anchorAmount: Decimal = 0
    /// CELIAPP only — lifetime contributions already made as of the anchor (0 for CELI).
    var lifetimeContributedAtAnchor: Decimal = 0
    /// REER only — estimated new contribution room accrued each year after the
    /// anchor (≈ 18% of earned income − pension adjustment). 0 = no projection.
    var annualRoomEstimate: Decimal = 0
    /// True if the anchor was entered Jan–Apr, when the CRA figure may be stale.
    var anchorSetInLagWindow: Bool = false
    var createdAt: Date = Date.now

    var registeredType: RegisteredType {
        get { RegisteredType(rawValue: registeredTypeRaw) ?? .celi }
        set { registeredTypeRaw = newValue.rawValue }
    }

    init(registeredType: RegisteredType,
         anchorYear: Int,
         anchorAmount: Decimal,
         lifetimeContributedAtAnchor: Decimal = 0,
         annualRoomEstimate: Decimal = 0,
         anchorSetInLagWindow: Bool = false) {
        self.registeredTypeRaw = registeredType.rawValue
        self.anchorYear = anchorYear
        self.anchorAmount = anchorAmount
        self.lifetimeContributedAtAnchor = lifetimeContributedAtAnchor
        self.annualRoomEstimate = annualRoomEstimate
        self.anchorSetInLagWindow = anchorSetInLagWindow
        self.createdAt = .now
    }
}

// MARK: - Aggregation service (bridges @Model data to the pure calculator)

enum RegisteredRoomService {
    /// All contribution/withdrawal entries across accounts of a given type
    /// (room is per person per type — archived accounts still count historically).
    static func entries(forType type: RegisteredType, in accounts: [Account]) -> [RegisteredEntryData] {
        accounts
            .filter { $0.registeredProfile?.registeredType == type }
            .flatMap { $0.transactions ?? [] }
            .filter { !$0.excludedFromRegisteredRoom && $0.status.countsTowardBalance }
            .map { RegisteredEntryData(date: $0.date, amount: $0.amount, isContribution: $0.type == .income) }
    }

    /// Available room for `type` given its plan + all accounts, as of `asOf`.
    /// Returns nil when no anchor plan has been set up yet.
    static func availableRoom(type: RegisteredType,
                              plan: RegisteredRoomPlan?,
                              accounts: [Account],
                              asOf: Date = .now) -> RoomResult? {
        guard let plan else { return nil }
        return RegisteredRoomCalculator.availableRoom(
            type: type,
            anchorYear: plan.anchorYear,
            anchorAmount: plan.anchorAmount,
            lifetimeContributedAtAnchor: plan.lifetimeContributedAtAnchor,
            reerAnnualRoom: plan.annualRoomEstimate,
            entries: entries(forType: type, in: accounts),
            asOf: asOf
        )
    }
}
