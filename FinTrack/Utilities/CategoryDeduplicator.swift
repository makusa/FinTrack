//
//  CategoryDeduplicator.swift
//  FinTrack
//
//  Collapses duplicate SYSTEM (seeded) categories created by the seed/CloudKit
//  race. SeedData inserts default categories keyed by French name on every
//  launch; with CloudKit, a locally-seeded set and the cloud set share names but
//  carry distinct persistent identifiers, so CloudKit keeps both -> duplicates.
//
//  Each (applicability, name) system group is collapsed to a single survivor and
//  any transactions are re-pointed onto it. The survivor is chosen
//  deterministically (earliest createdAt -- a synced, per-record-stable field) so
//  every device converges on the same keeper without deleting each other's copy.
//
//  Only system categories are touched: user-created categories are deliberate and
//  must never be auto-merged. Idempotent and cheap; safe to call repeatedly.
//

import Foundation
import SwiftData

enum CategoryDeduplicator {

    @discardableResult
    static func dedupeSystemCategories(context: ModelContext) -> Int {
        let descriptor = FetchDescriptor<Category>(predicate: #Predicate { $0.isSystem })
        let system = (try? context.fetch(descriptor)) ?? []
        guard system.count > 1 else { return 0 }

        var groups: [String: [Category]] = [:]
        for cat in system {
            let key = "\(cat.applicabilityRaw)|\(cat.name)"
            groups[key, default: []].append(cat)
        }

        var removed = 0
        for (_, dupes) in groups where dupes.count > 1 {
            let ordered = dupes.sorted { $0.createdAt < $1.createdAt }
            let survivor = ordered[0]
            let keepVisible = !dupes.allSatisfy { $0.isHidden }

            for dupe in ordered.dropFirst() {
                for tx in (dupe.transactions ?? []) {
                    tx.category = survivor
                }
                context.delete(dupe)
                removed += 1
            }
            survivor.isHidden = !keepVisible
        }

        if removed > 0 {
            do { try context.save() }
            catch { AppLogger.seed.error("CategoryDeduplicator save failed: \(error, privacy: .private)") }
        }
        return removed
    }
}
