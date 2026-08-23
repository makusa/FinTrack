//  RecurrenceDetector.swift — On-device recurring-payment detection (paid AI, Phase 2)
//
//  Pure analysis over the user's own history — 100% on-device, no cost. Groups
//  cleared transactions by merchant + amount, checks the intervals are regular,
//  classifies the frequency, and skips anything an active rule already covers or
//  the user has dismissed. Results PRE-FILL a suggestion the user accepts or ignores.
import Foundation
import SwiftData

enum RecurrenceDetector {

    struct Suggestion: Identifiable {
        let id: String            // stable key (type|merchant|amount) — used for dismissals
        let payee: String
        let amount: Decimal
        let currency: String
        let type: TransactionType
        let frequency: RecurrenceFrequency
        let category: Category?
        let account: Account?
        let lastDate: Date
        let count: Int
    }

    /// Minimum occurrences before we trust a pattern.
    private static let minOccurrences = 3

    static func detect(in context: ModelContext, dismissed: Set<String> = []) -> [Suggestion] {
        let all = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
        let now = Date.now
        // Real, past, non-transfer, non-generated rows with a payee.
        let candidates = all.filter { tx in
            tx.payee != nil && tx.transferPairId == nil && tx.sourceRecurringId == nil
                && tx.date <= now && (tx.status == .cleared || tx.status == .reconciled)
        }

        // Merchants already covered by an active rule — don't re-suggest them.
        let rules = (try? context.fetch(FetchDescriptor<RecurringTransaction>())) ?? []
        let covered = Set(rules.filter { $0.isActive }
            .compactMap { $0.payee.map { SmartCategorizer.normalize($0) } }
            .filter { !$0.isEmpty })

        // Group by type + normalized merchant + rounded amount.
        var groups: [String: [Transaction]] = [:]
        for tx in candidates {
            guard let payee = tx.payee else { continue }
            let merchant = SmartCategorizer.normalize(payee)
            guard !merchant.isEmpty, !covered.contains(merchant) else { continue }
            let rounded = (tx.amount as NSDecimalNumber).intValue
            groups["\(tx.typeRaw)|\(merchant)|\(rounded)", default: []].append(tx)
        }

        var suggestions: [Suggestion] = []
        for (key, txs) in groups where txs.count >= minOccurrences && !dismissed.contains(key) {
            guard let freq = detectFrequency(txs) else { continue }
            let sorted = txs.sorted { $0.date < $1.date }
            guard let last = sorted.last else { continue }
            suggestions.append(Suggestion(
                id: key,
                payee: last.payee ?? "",
                amount: medianAmount(txs),
                currency: last.account?.currency ?? Currencies.default,
                type: last.type,
                frequency: freq,
                category: last.category,
                account: last.account,
                lastDate: last.date,
                count: txs.count
            ))
        }
        // Most-recurring first (more occurrences = more confidence).
        return suggestions.sorted { $0.count > $1.count }
    }

    // MARK: - Frequency + regularity

    /// Median interval → frequency, but only if intervals are regular enough
    /// (a handful of random purchases at one merchant must not look recurring).
    private static func detectFrequency(_ txs: [Transaction]) -> RecurrenceFrequency? {
        let dates = txs.map(\.date).sorted()
        let intervals = zip(dates, dates.dropFirst()).map { $1.timeIntervalSince($0) / 86_400 }
        guard intervals.count >= 2 else { return nil }
        let median = medianOf(intervals)
        guard let freq = classify(medianDays: median) else { return nil }
        // At least 60% of intervals within ±40% of the median.
        let tol = median * 0.4
        let regular = intervals.filter { abs($0 - median) <= tol }.count
        guard Double(regular) >= ceil(Double(intervals.count) * 0.6) else { return nil }
        return freq
    }

    private static func classify(medianDays d: Double) -> RecurrenceFrequency? {
        switch d {
        case 0.5..<3:    return .daily
        case 3..<11:     return .weekly
        case 11..<20:    return .biweekly
        case 20..<45:    return .monthly
        case 45..<180:   return .quarterly
        case 180..<450:  return .yearly
        default:         return nil
        }
    }

    // MARK: - Helpers

    private static func medianOf(_ values: [Double]) -> Double {
        let s = values.sorted()
        guard !s.isEmpty else { return 0 }
        let mid = s.count / 2
        return s.count % 2 == 0 ? (s[mid - 1] + s[mid]) / 2 : s[mid]
    }

    private static func medianAmount(_ txs: [Transaction]) -> Decimal {
        let s = txs.map(\.amount).sorted { $0 < $1 }
        guard !s.isEmpty else { return 0 }
        return s[s.count / 2]
    }
}
