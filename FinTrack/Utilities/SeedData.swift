//
//  SeedData.swift
//  FinTrack
//
//  Seeds default categories on first launch.
//  Re-running is idempotent: it only inserts categories that are missing by name.
//

import Foundation
import SwiftData

enum SeedData {
    /// Default expense categories (FR labels), in display order.
    private static let expenseCategories: [(name: String, icon: String, color: String)] = [
        ("Alimentation",            "cart.fill",                "#34C759"),
        ("Restaurant",              "fork.knife",               "#FF9500"),
        ("Transport",               "car.fill",                 "#3478F6"),
        ("Logement",                "house.fill",               "#A2845E"),
        ("Services publics",        "bolt.fill",                "#FFCC00"),
        ("Santé",                   "cross.case.fill",          "#FF3B30"),
        ("Loisirs",                 "film.fill",                "#AF52DE"),
        ("Vêtements",               "tshirt.fill",              "#FF2D92"),
        ("Éducation",               "book.fill",                "#5AC8FA"),
        ("Voyage",                  "airplane",                 "#3478F6"),
        ("Cadeaux",                 "gift.fill",                "#FF2D92"),
        ("Frais bancaires",         "building.columns",         "#8E8E93"),
        ("Impôts",                  "doc.text.fill",            "#8E8E93"),
        ("Famille (transferts)",    "globe",                    "#34C759"),
        ("Autre dépense",           "ellipsis.circle.fill",     "#8E8E93"),
    ]

    /// Default income categories (FR labels).
    private static let incomeCategories: [(name: String, icon: String, color: String)] = [
        ("Salaire",         "briefcase.fill",                    "#34C759"),
        ("Bonus",           "star.fill",                         "#FFCC00"),
        ("Dividendes",      "chart.line.uptrend.xyaxis",         "#3478F6"),
        ("Intérêts",        "percent",                           "#5AC8FA"),
        ("Remboursement",   "arrow.uturn.backward.circle.fill",  "#34C759"),
        ("Cadeau reçu",     "gift.fill",                         "#FF2D92"),
        ("Autre revenu",    "ellipsis.circle.fill",              "#8E8E93"),
    ]

    /// Inserts any missing default categories. Safe to call on every launch.
    static func seedIfNeeded(context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<Category>())) ?? []
        let existingNames = Set(existing.map { $0.name })

        for entry in expenseCategories where !existingNames.contains(entry.name) {
            context.insert(Category(
                name: entry.name,
                iconSystemName: entry.icon,
                colorHex: entry.color,
                applicability: .expense,
                isSystem: true
            ))
        }
        for entry in incomeCategories where !existingNames.contains(entry.name) {
            context.insert(Category(
                name: entry.name,
                iconSystemName: entry.icon,
                colorHex: entry.color,
                applicability: .income,
                isSystem: true
            ))
        }

        do {
            try context.save()
        } catch {
            // Non-fatal: seeding will retry next launch.
            print("SeedData: save failed — \(error)")
        }
    }
}
