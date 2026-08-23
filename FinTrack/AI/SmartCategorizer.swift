//  SmartCategorizer.swift — On-device smart categorisation (paid AI, Phase 1)
//
//  Learns purely from the user's OWN categorised transactions: merchant → the
//  category they most often use for it. No Core ML model, no network, no marginal
//  cost — 100% on-device, consistent with FinTrack's local-first positioning.
//
//  Two entry points:
//   • suggest(payee:type:in:)  — one-shot, for manual entry (debounced by caller).
//   • buildModel(in:) + Model.suggest(payee:type:) — build the index ONCE, query it
//     many times, for batch use at bank import (avoids a fetch per transaction).
//
//  Intent-neutral (no entitlement checks): the caller gates on the user's tier.
import Foundation
import SwiftData

enum SmartCategorizer {

    // MARK: One-shot (manual entry)

    static func suggest(payee: String?, type: TransactionType, in context: ModelContext) -> Category? {
        buildModel(in: context).suggest(payee: payee, type: type)
    }

    // MARK: Pre-built model (batch: bank import)

    /// A learned merchant→category index. Value type; holds Category references from
    /// the context it was built with — use it on the same actor/context.
    struct Model {
        fileprivate struct Bucket { var scores: [PersistentIdentifier: (cat: Category, score: Double)] = [:] }
        fileprivate var exact:  [String: Bucket] = [:]   // key: "typeRaw\u{1}payeeNorm"
        fileprivate var token:  [String: Bucket] = [:]   // key: "typeRaw\u{1}token"

        /// Suggest a category for this payee+type, or nil if no confident match.
        func suggest(payee: String?, type: TransactionType) -> Category? {
            guard let raw = payee?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
            let key = SmartCategorizer.normalize(raw)
            guard !key.isEmpty else { return nil }
            let t = type.rawValue

            // 1) Exact normalised-merchant match → best-scoring category.
            if let b = exact["\(t)\u{1}\(key)"],
               let best = b.scores.values.max(by: { $0.score < $1.score }) {
                return best.cat
            }
            // 2) Fallback: any shared significant word.
            var tally: [PersistentIdentifier: (cat: Category, score: Double)] = [:]
            for tok in Set(key.split(separator: " ").map(String.init)) {
                if let b = token["\(t)\u{1}\(tok)"] {
                    for (id, e) in b.scores { tally[id, default: (e.cat, 0)].score += e.score }
                }
            }
            return tally.values.max(by: { $0.score < $1.score })?.cat
        }
    }

    /// Build the index from all the user's categorised transactions — one fetch.
    static func buildModel(in context: ModelContext) -> Model {
        var model = Model()
        let all = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
        for tx in all {
            guard let cat = tx.category, let p = tx.payee else { continue }
            let key = normalize(p)
            guard !key.isEmpty else { continue }
            let t = tx.typeRaw
            let w = recencyWeight(tx.date)

            model.exact["\(t)\u{1}\(key)", default: Model.Bucket()]
                .scores[cat.persistentModelID, default: (cat, 0)].score += w
            for tok in Set(key.split(separator: " ").map(String.init)) {
                model.token["\(t)\u{1}\(tok)", default: Model.Bucket()]
                    .scores[cat.persistentModelID, default: (cat, 0)].score += w
            }
        }
        return model
    }

    // MARK: Helpers

    /// Normalise a merchant string: lowercase, keep letters only, drop short tokens
    /// (bank prefixes like "SQ", "POS"), collapse whitespace. So "SQ *COFFEE 0123"
    /// and "COFFEE SHOP" both land on "coffee".
    static func normalize(_ s: String) -> String {
        let lowered = s.lowercased()
        var out = ""
        out.unicodeScalars.reserveCapacity(lowered.unicodeScalars.count)
        for scalar in lowered.unicodeScalars {
            if CharacterSet.letters.contains(scalar) { out.unicodeScalars.append(scalar) }
            else { out.append(" ") }
        }
        return out.split(separator: " ").map(String.init).filter { $0.count > 2 }.joined(separator: " ")
    }

    /// Recent categorisations weigh more. Half-life ~180 days, floored at 0.2.
    private static func recencyWeight(_ date: Date) -> Double {
        let days = max(0, Date.now.timeIntervalSince(date) / 86_400)
        return max(0.2, pow(0.5, days / 180))
    }
}
