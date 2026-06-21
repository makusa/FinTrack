//
//  EmbeddingMatcher.swift
//  FinTrack
//
//  Pure nearest-neighbour selection over text embeddings (phase B). Given a query
//  vector and the user's categorized-history vectors, it returns the category of
//  the closest cluster by cosine similarity, via a top-k weighted vote — but ONLY
//  if the single closest neighbour clears `minSimilarity`. Conservative on purpose:
//  embeddings on cryptic merchant codes are weak, so below the bar we return nil
//  and let the result stay blank rather than guess.
//
//  Pure (vectors in, key out) so it is unit-tested with swiftc; the actual
//  embedding (NaturalLanguage) lives in SemanticCategorizer.
//

import Foundation

enum EmbeddingMatcher {
    struct Labeled {
        let vector: [Double]
        let categoryKey: String
    }

    static func cosine(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return -1 }
        var dot = 0.0, na = 0.0, nb = 0.0
        for i in a.indices { dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i] }
        guard na > 0, nb > 0 else { return -1 }
        return dot / (na.squareRoot() * nb.squareRoot())
    }

    static func best(query: [Double], among labeled: [Labeled],
                     k: Int = 5, minSimilarity: Double) -> String? {
        guard !query.isEmpty, !labeled.isEmpty else { return nil }
        let ranked = labeled.map { ($0.categoryKey, cosine(query, $0.vector)) }
            .filter { $0.1.isFinite }
            .sorted { $0.1 > $1.1 }
        guard let top = ranked.first, top.1 >= minSimilarity else { return nil }
        var score: [String: Double] = [:]
        for (key, sim) in ranked.prefix(k) { score[key, default: 0] += max(0, sim) }
        return score.max(by: { a, b in a.value != b.value ? a.value < b.value : a.key > b.key })?.key
    }
}
