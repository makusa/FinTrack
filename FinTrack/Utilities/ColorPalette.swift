//
//  ColorPalette.swift
//  FinTrack
//
//  Hex string ↔ SwiftUI Color, plus a curated palette so all accounts share
//  a visually coherent look.
//

import SwiftUI

extension Color {
    init(hex: String) {
        let cleaned = hex.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespaces)
        var rgb: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&rgb)
        let r = Double((rgb & 0xFF0000) >> 16) / 255
        let g = Double((rgb & 0x00FF00) >> 8)  / 255
        let b = Double( rgb & 0x0000FF)        / 255
        self.init(red: r, green: g, blue: b)
    }
}

enum ColorPalette {
    /// Hand-picked palette for accounts. Avoids clashing hues; works in light/dark.
    static let accountColors: [String] = [
        "#3478F6", // blue
        "#34C759", // green
        "#FF9500", // orange
        "#FF3B30", // red
        "#AF52DE", // purple
        "#5AC8FA", // teal
        "#FFCC00", // yellow
        "#8E8E93", // gray
        "#A2845E", // brown
        "#FF2D92", // pink
    ]

    /// Palette for categories. Similar set; categories can also reuse account colors.
    static let categoryColors: [String] = accountColors
}
