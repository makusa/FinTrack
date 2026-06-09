//  WidgetData.swift — Shared between main app and WidgetKit extension
//  Serialised as JSON in App Group UserDefaults (group.ca.regis.fintrack)

import Foundation

struct FinTrackWidgetData: Codable {
    static let appGroupID      = "group.ca.regis.fintrack"
    static let userDefaultsKey = "fintrack.widget.data"

    let primaryCurrency: String
    let balances: [BalanceEntry]
    let netWorth: Double
    let monthIncome: Double
    let monthExpense: Double
    let recentTransactions: [WidgetTx]
    let upcoming: [WidgetEvent]
    let updatedAt: Date

    struct BalanceEntry: Codable, Identifiable {
        var id: String { currency }
        let currency: String
        let symbol: String
        let amount: Double
    }

    struct WidgetTx: Codable, Identifiable {
        let id: UUID
        let label: String
        let amount: Double
        let currency: String
        let isIncome: Bool
    }

    struct WidgetEvent: Codable, Identifiable {
        let id: UUID
        let name: String
        let amount: Double
        let currency: String
        let daysUntil: Int
    }

    static func load() -> FinTrackWidgetData {
        guard let defaults = UserDefaults(suiteName: FinTrackWidgetData.appGroupID),
              let data = defaults.data(forKey: userDefaultsKey),
              let decoded = try? JSONDecoder().decode(FinTrackWidgetData.self, from: data)
        else { return .placeholder }
        return decoded
    }

    func save() {
        guard let defaults = UserDefaults(suiteName: FinTrackWidgetData.appGroupID),
              let encoded = try? JSONEncoder().encode(self) else { return }
        defaults.set(encoded, forKey: Self.userDefaultsKey)
    }

    static let placeholder = FinTrackWidgetData(
        primaryCurrency: "CAD",
        balances: [BalanceEntry(currency: "CAD", symbol: "$ CA", amount: 0)],
        netWorth: 0, monthIncome: 0, monthExpense: 0,
        recentTransactions: [], upcoming: [], updatedAt: .now
    )

    func formatted(_ amount: Double, currency: String) -> String {
        let sym = balances.first(where: { $0.currency == currency })?.symbol ?? currency
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal
        fmt.minimumFractionDigits = 0
        fmt.maximumFractionDigits = 2
        return "\(fmt.string(from: NSNumber(value: amount)) ?? "\(amount)") \(sym)"
    }

    func formattedShort(_ amount: Double) -> String {
        let a = Swift.abs(amount)
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal
        fmt.maximumFractionDigits = 0
        if a >= 1_000_000 { return (fmt.string(from: NSNumber(value: a/1_000_000)) ?? "") + "M" }
        if a >= 1_000     { return (fmt.string(from: NSNumber(value: a/1_000))     ?? "") + "k" }
        return fmt.string(from: NSNumber(value: a)) ?? "\(a)"
    }
}
