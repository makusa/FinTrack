//  FinTrackWidgetComponents.swift — Shared "Focus" visual language for all widgets
//  Side accent bar, hero amount, trend pill, month bar. Keeps the Home-screen
//  widgets (Small/Medium/Large) and the registered-room widget visually consistent.
import SwiftUI
import WidgetKit

/// Hero number colour: primary normally, red when the value itself is negative.
func heroColor(_ v: Double) -> Color { v >= 0 ? .primary : .red }

/// Trend colour: green when up (or flat), orange when down.
func trendColor(_ change: Double) -> Color { change >= 0 ? .green : .orange }

/// Vertical coloured accent bar — the Focus signature.
struct SideAccent: View {
    var color: Color = .green
    var body: some View {
        RoundedRectangle(cornerRadius: 2.5)
            .fill(color)
            .frame(width: 5)
            .padding(.vertical, 2)
    }
}

/// Hero amount: exact number (rounded, heavy) with the currency symbol kept small
/// beside it. `style` lets each widget size the number to its space.
struct HeroAmount: View {
    let data: FinTrackWidgetData
    let amount: Double
    var style: Font.TextStyle = .largeTitle
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(data.formattedFull(amount))
                .font(.system(style, design: .rounded).weight(.heavy))
                .minimumScaleFactor(0.4).lineLimit(1)
                .foregroundStyle(heroColor(amount))
            Text(data.balances.first(where: { $0.currency == data.primaryCurrency })?.symbol ?? data.primaryCurrency)
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }
    }
}

/// Coloured pill for the net-worth month change (option B). Arrow + amount + "this month".
struct TrendPill: View {
    let data: FinTrackWidgetData
    var compact: Bool = false
    var body: some View {
        let change = data.netWorthMonthChange
        let up = change >= 0
        let accent = trendColor(change)
        return HStack(spacing: 3) {
            Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: compact ? 9 : 10, weight: .bold))
            Text("\(data.formattedShort(change)) \(data.str("thisMonth"))")
                .font(.caption2.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .foregroundStyle(accent)
        .padding(.vertical, compact ? 2 : 4).padding(.horizontal, compact ? 7 : 9)
        .background(accent.opacity(0.15), in: Capsule())
    }
}

/// Stacked income-vs-expense bar (green share = income, red share = expense).
struct MonthBar: View {
    let income: Double
    let expense: Double
    var body: some View {
        GeometryReader { geo in
            let total = max(income + expense, 1)
            HStack(spacing: 0) {
                Rectangle().fill(.green).frame(width: geo.size.width * (income / total))
                Rectangle().fill(.red.opacity(0.85))
            }
            .clipShape(Capsule())
        }
    }
}

/// Small label used above hero numbers.
struct WidgetCaption: View {
    let text: String
    var body: some View {
        Text(text).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            .lineLimit(1).minimumScaleFactor(0.8)
    }
}

extension Color {
    /// Hex string → Color (the app's own Color(hex:) isn't in the widget target).
    init(widgetHex hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        var rgb: UInt64 = 0
        Scanner(string: s).scanHexInt64(&rgb)
        self.init(.sRGB,
                  red:   Double((rgb >> 16) & 0xFF) / 255,
                  green: Double((rgb >> 8) & 0xFF) / 255,
                  blue:  Double(rgb & 0xFF) / 255)
    }
}
