//
//  SemanticCategorizer.swift
//  FinTrack
//
//  Impure half of phase B: on-device text embeddings via NaturalLanguage, plus a
//  lazily-built index over the user's distinct historical merchants. Aggregation
//  (distinct payee → dominant category per side) is cheap and eager; the expensive
//  embedding is deferred to the first query, so imports fully resolved by memory +
//  dictionary never pay the cost. Selection logic lives in the pure EmbeddingMatcher.
//

import Foundation
import NaturalLanguage

struct NLEmbeddingProvider {
    private let fr = NLEmbedding.sentenceEmbedding(for: .french)
    private let en = NLEmbedding.sentenceEmbedding(for: .english)

    /// Vector for a normalized payee (lowercased for the model), French then
    /// English; nil if no embedding asset is available or the text can't embed.
    func vector(for normalizedPayee: String) -> [Double]? {
        let text = normalizedPayee.lowercased()
        guard !text.isEmpty else { return nil }
        return fr?.vector(for: text) ?? en?.vector(for: text)
    }
}

final class SemanticIndex {
    private struct Entry { let payeeNorm: String; let categoryKey: String; let isIncome: Bool }

    private let entries: [Entry]
    private let provider = NLEmbeddingProvider()
    private var built = false
    private var income: [EmbeddingMatcher.Labeled] = []
    private var expense: [EmbeddingMatcher.Labeled] = []

    init(history: [(payee: String, categoryKey: String, isIncome: Bool)]) {
        // distinct (side, normalizedPayee) → dominant category
        var agg: [String: [String: Int]] = [:]
        for h in history {
            let key = PayeeNormalizer.normalize(h.payee)
            guard !key.isEmpty else { continue }
            agg["\(h.isIncome)|\(key)", default: [:]][h.categoryKey, default: 0] += 1
        }
        entries = agg.compactMap { compound, counts in
            guard let dominant = counts.max(by: { $0.value < $1.value })?.key else { return nil }
            let parts = compound.split(separator: "|", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            return Entry(payeeNorm: String(parts[1]), categoryKey: dominant, isIncome: parts[0] == "true")
        }
    }

    func suggestion(name: String, isIncome: Bool, eligible: Set<String>, minSimilarity: Double) -> String? {
        buildIfNeeded()
        guard let query = provider.vector(for: PayeeNormalizer.normalize(name)) else { return nil }
        let pool = (isIncome ? income : expense).filter { eligible.contains($0.categoryKey) }
        return EmbeddingMatcher.best(query: query, among: pool, minSimilarity: minSimilarity)
    }

    private func buildIfNeeded() {
        guard !built else { return }
        built = true
        for e in entries {
            guard let v = provider.vector(for: e.payeeNorm) else { continue }
            let labeled = EmbeddingMatcher.Labeled(vector: v, categoryKey: e.categoryKey)
            if e.isIncome { income.append(labeled) } else { expense.append(labeled) }
        }
    }
}
