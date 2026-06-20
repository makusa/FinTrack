//
//  RegisteredModels.swift
//  FinTrack
//
//  SwiftData persistence for registered accounts, plus the localized labels
//  for the (pure) RegisteredType. The contribution-room MATH lives in
//  RegisteredRoom.swift; these types only store data and bridge to it.
//
//  Three pieces:
//   • RegisteredAccountProfile — 1:1 tag on an Account (this is a CELI/CELIAPP…).
//   • RegisteredRoomPlan       — the per-type anchor (room is per person per type).
//   • RegisteredEntry          — a contribution or withdrawal (like CreditLineEntry).
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

// MARK: - Entry kind

enum RegisteredEntryKind: String, CaseIterable, Identifiable {
    case contribution
    case withdrawal

    var id: String { rawValue }

    var label: String {
        switch self {
        case .contribution: return LanguageManager.shared["reg.entry.contribution"]
        case .withdrawal:   return LanguageManager.shared["reg.entry.withdrawal"]
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
         anchorSetInLagWindow: Bool = false) {
        self.registeredTypeRaw = registeredType.rawValue
        self.anchorYear = anchorYear
        self.anchorAmount = anchorAmount
        self.lifetimeContributedAtAnchor = lifetimeContributedAtAnchor
        self.anchorSetInLagWindow = anchorSetInLagWindow
        self.createdAt = .now
    }
}

// MARK: - Contribution / withdrawal entry

@Model
final class RegisteredEntry {
    var kindRaw: String = RegisteredEntryKind.contribution.rawValue
    var amount: Decimal = 0   // always positive
    var date: Date = Date.now
    var note: String = ""
    var createdAt: Date = Date.now

    // inverse + cascade declared on Account.registeredEntries.
    var account: Account?

    var kind: RegisteredEntryKind {
        get { RegisteredEntryKind(rawValue: kindRaw) ?? .contribution }
        set { kindRaw = newValue.rawValue }
    }

    /// Plain value for the pure RegisteredRoomCalculator.
    var asData: RegisteredEntryData {
        RegisteredEntryData(date: date, amount: amount, isContribution: kind == .contribution)
    }

    init(kind: RegisteredEntryKind, amount: Decimal, date: Date = .now, note: String = "") {
        self.kindRaw = kind.rawValue
        self.amount = amount
        self.date = date
        self.note = note
        self.createdAt = .now
    }
}
