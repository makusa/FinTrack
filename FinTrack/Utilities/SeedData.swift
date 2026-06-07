//
//  SeedData.swift
//  FinTrack
//
//  Seeds default categories on first launch.
//  Re-running is idempotent: inserts missing categories and updates
//  localizationKey on existing system categories.
//

import Foundation
import SwiftData

enum SeedData {

    // (name in FR, localizationKey, icon, color)
    private static let expenseCategories: [(name: String, key: String, icon: String, color: String)] = [
        ("Alimentation",         "category.grocery",       "cart.fill",                "#34C759"),
        ("Restaurant",           "category.restaurant",    "fork.knife",               "#FF9500"),
        ("Transport",            "category.transport",     "car.fill",                 "#3478F6"),
        ("Logement",             "category.housing",       "house.fill",               "#A2845E"),
        ("Services publics",     "category.utilities",     "bolt.fill",                "#FFCC00"),
        ("Santé",                "category.health",        "cross.case.fill",          "#FF3B30"),
        ("Loisirs",              "category.entertainment", "film.fill",                "#AF52DE"),
        ("Vêtements",            "category.clothing",      "tshirt.fill",              "#FF2D92"),
        ("Éducation",            "category.education",     "book.fill",                "#5AC8FA"),
        ("Voyage",               "category.travel",        "airplane",                 "#3478F6"),
        ("Cadeaux",              "category.gifts",         "gift.fill",                "#FF2D92"),
        ("Frais bancaires",      "category.banking",       "building.columns",         "#8E8E93"),
        ("Impôts",               "category.taxes",         "doc.text.fill",            "#8E8E93"),
        ("Famille (transferts)", "category.family",        "globe",                    "#34C759"),
        ("Autre dépense",        "category.other.expense", "ellipsis.circle.fill",     "#8E8E93"),
    ]

    private static let incomeCategories: [(name: String, key: String, icon: String, color: String)] = [
        ("Salaire",       "category.salary",        "briefcase.fill",                   "#34C759"),
        ("Bonus",         "category.bonus",          "star.fill",                        "#FFCC00"),
        ("Dividendes",    "category.dividends",      "chart.line.uptrend.xyaxis",        "#3478F6"),
        ("Intérêts",      "category.interest",       "percent",                          "#5AC8FA"),
        ("Remboursement", "category.refund",         "arrow.uturn.backward.circle.fill", "#34C759"),
        ("Cadeau reçu",   "category.gift.received",  "gift.fill",                        "#FF2D92"),
        ("Autre revenu",  "category.other.income",   "ellipsis.circle.fill",             "#8E8E93"),
    ]

    /// Inserts missing default categories and patches localizationKey on existing ones.
    static func seedIfNeeded(context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<Category>())) ?? []

        // Build lookup by French name for the update pass
        let existingByName: [String: Category] = Dictionary(
            existing.map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var didChange = false

        // Insert missing + patch localizationKey for all system categories
        for entry in expenseCategories {
            if let cat = existingByName[entry.name] {
                // Patch key if missing
                if cat.localizationKey != entry.key {
                    cat.localizationKey = entry.key
                    didChange = true
                }
            } else {
                context.insert(Category(
                    name: entry.name,
                    localizationKey: entry.key,
                    iconSystemName: entry.icon,
                    colorHex: entry.color,
                    applicability: .expense,
                    isSystem: true
                ))
                didChange = true
            }
        }

        for entry in incomeCategories {
            if let cat = existingByName[entry.name] {
                if cat.localizationKey != entry.key {
                    cat.localizationKey = entry.key
                    didChange = true
                }
            } else {
                context.insert(Category(
                    name: entry.name,
                    localizationKey: entry.key,
                    iconSystemName: entry.icon,
                    colorHex: entry.color,
                    applicability: .income,
                    isSystem: true
                ))
                didChange = true
            }
        }

        if didChange {
            do { try context.save() } catch {
                print("SeedData: save failed — \(error)")
            }
        }
    }
}
