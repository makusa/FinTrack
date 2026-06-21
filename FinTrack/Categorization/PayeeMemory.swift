//
//  PayeeMemory.swift
//  FinTrack
//
//  Personalized merchant → category memory, derived from the user's already-
//  categorized transactions. Exact (normalized) payee match: the strongest and
//  cheapest signal, and it covers custom categories for free. Type-aware, so a
//  counterparty you both pay and receive from doesn't cross income/expense wires.
//
//  Pure (depends only on PayeeNormalizer). Rebuilt from history at each import,
//  so the user's corrections are absorbed automatically — no separate store to
//  keep in sync, no stale rules.
//

import Foundation

struct PayeeMemory {
    // normalizedPayee → isIncome → categoryKey → count
    private var index: [String: [Bool: [String: Int]]] = [:]

    init(history: [(payee: String, categoryKey: String, isIncome: Bool)]) {
        for entry in history {
            let key = PayeeNormalizer.normalize(entry.payee)
            guard !key.isEmpty else { continue }
            index[key, default: [:]][entry.isIncome, default: [:]][entry.categoryKey, default: 0] += 1
        }
    }

    /// Most-frequent category key seen for this payee on the given side.
    /// Ties resolve to the lexicographically smallest key (deterministic).
    func suggestion(for payee: String, isIncome: Bool) -> String? {
        let key = PayeeNormalizer.normalize(payee)
        guard !key.isEmpty, let counts = index[key]?[isIncome], !counts.isEmpty else { return nil }
        return counts.max(by: { a, b in
            a.value != b.value ? a.value < b.value : a.key > b.key
        })?.key
    }

    var isEmpty: Bool { index.isEmpty }
}
