//  SmartCategorizer.swift — On-device smart categorisation (Placement/paid AI, Phase 1)
//
//  Learns purely from the user's OWN categorised transactions: merchant → the
//  category they most often use for it. No Core ML model, no network, no marginal
//  cost — 100% on-device, consistent with FinTrack's local-first positioning.
//  Every time the user categorises or corrects a transaction, this gets better.
//
//  This type is intent-neutral (no entitlement checks): the caller decides whether
//  to offer suggestions based on the user's tier.
import Foundation
import SwiftData

enum SmartCategorizer {

    /// Suggest a category for a transaction with this payee and type, based on how
    /// the user has categorised the same (or a similar) merchant before. Returns
    /// nil when there's no confident match.
    static func suggest(payee: String?, type: TransactionType, in context: ModelContext) -> Category? {
        guard let raw = payee?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let key = normalize(raw)
        guard !key.isEmpty else { return nil }
        let keyTokens = Set(key.split(separator: " ").map(String.init))

        // Learn from the user's own categorised history of the same type.
        // Fetch by typeRaw (safe in #Predicate), filter relations in memory.
        let typeRaw = type.rawValue
        let descriptor = FetchDescriptor<Transaction>(predicate: #Predicate { $0.typeRaw == typeRaw })
        guard let all = try? context.fetch(descriptor) else { return nil }

        var exact: [PersistentIdentifier: (cat: Category, score: Double)] = [:]
        var fuzzy: [PersistentIdentifier: (cat: Category, score: Double)] = [:]

        for tx in all {
            guard let cat = tx.category, let p = tx.payee else { continue }
            let pk = normalize(p)
            guard !pk.isEmpty else { continue }
            let weight = recencyWeight(tx.date)
            if pk == key {
                exact[cat.persistentModelID, default: (cat, 0)].score += weight
            } else {
                let toks = Set(pk.split(separator: " ").map(String.init))
                if !keyTokens.isDisjoint(with: toks) {
                    fuzzy[cat.persistentModelID, default: (cat, 0)].score += weight
                }
            }
        }

        // Prefer an exact merchant match; otherwise fall back to a shared-word match.
        if let best = exact.values.max(by: { $0.score < $1.score }) { return best.cat }
        if let best = fuzzy.values.max(by: { $0.score < $1.score }) { return best.cat }
        return nil
    }

    /// Normalise a merchant string: lowercase, keep letters only, drop short tokens
    /// (bank prefixes like "SQ", "POS", "TX"), collapse whitespace. This makes
    /// "SQ *COFFEE 0123" and "COFFEE SHOP" land on the same "coffee".
    static func normalize(_ s: String) -> String {
        let lowered = s.lowercased()
        var out = ""
        out.unicodeScalars.reserveCapacity(lowered.unicodeScalars.count)
        for scalar in lowered.unicodeScalars {
            if CharacterSet.letters.contains(scalar) {
                out.unicodeScalars.append(scalar)
            } else {
                out.append(" ")
            }
        }
        let tokens = out.split(separator: " ").map(String.init).filter { $0.count > 2 }
        return tokens.joined(separator: " ")
    }

    /// Recent categorisations weigh more — the user's habits evolve over time.
    /// Half-life ~180 days, floored so old data still contributes.
    private static func recencyWeight(_ date: Date) -> Double {
        let days = max(0, Date.now.timeIntervalSince(date) / 86_400)
        return max(0.2, pow(0.5, days / 180))
    }
}
