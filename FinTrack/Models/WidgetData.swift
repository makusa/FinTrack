//  WidgetData.swift — Shared between main app and WidgetKit extension
//  Serialised as JSON in App Group UserDefaults (group.ca.regis.fintrack)
//
//  The widget extension can't reach the app's LanguageManager, so the app writes
//  the in-app language code here and the widget looks labels up in `widgetStrings`
//  below. This keeps widgets in sync with the language chosen inside the app
//  (not the system language).

import Foundation

struct FinTrackWidgetData: Codable {
    static let appGroupID      = "group.ca.regis.fintrack"
    static let userDefaultsKey = "fintrack.widget.data"

    let primaryCurrency: String
    let language: String                       // "fr" | "en" | "es" | "pt"
    let balances: [BalanceEntry]
    let netWorth: Double                       // true net worth, converted to primaryCurrency
    let netWorthMonthChange: Double            // Δ net worth since the start of the month
    let monthIncome: Double
    let monthExpense: Double
    let recentTransactions: [WidgetTx]
    let upcoming: [WidgetEvent]
    let registeredRooms: [RegisteredRoomEntry]
    let budgets: [WidgetBudget]
    let budgetTransactions: [WidgetBudgetTx]
    let accounts: [WidgetAccount]
    let accountsTotal: Double                  // sum of account balances, in primaryCurrency
    let savings: [WidgetSavings]
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

    /// Contribution room for one registered-account type (CELI / CELIAPP / REER).
    struct RegisteredRoomEntry: Codable, Identifiable {
        var id: String { type }
        let type: String            // "celi" | "celiapp" | "reer"
        let shortName: String       // "CELI"
        let available: Double
        let contributed: Double
        let lifetimeCap: Double?     // 40000 for CELIAPP, nil otherwise
        let isOver: Bool

        /// Used fraction (0…1): contributed / relevant ceiling. Lifetime cap when
        /// it exists (CELIAPP), else contributed + available (room since anchor).
        var usedFraction: Double {
            let denom = lifetimeCap ?? (contributed + Swift.max(available, 0))
            guard denom > 0 else { return isOver ? 1 : 0 }
            return Swift.min(Swift.max(contributed / denom, 0), 1)
        }
    }

    /// One active budget: spent vs limit, with its colour.
    struct WidgetBudget: Codable, Identifiable {
        let id: String
        let name: String
        let spent: Double
        let limit: Double
        let currency: String
        let colorHex: String
        var fraction: Double { limit > 0 ? Swift.min(spent / limit, 1) : 0 }
        var isOver: Bool { spent > limit }
    }

    /// A recent expense that counts toward a budget, tagged with that budget's colour.
    struct WidgetBudgetTx: Codable, Identifiable {
        let id: UUID
        let label: String
        let amount: Double
        let currency: String
        let colorHex: String
    }

    /// One active account: name, balance, currency, colour, icon.
    struct WidgetAccount: Codable, Identifiable {
        let id: String
        let name: String
        let balance: Double
        let currency: String
        let colorHex: String
        let icon: String
    }

    /// One active savings project: saved so far vs (optional) target.
    struct WidgetSavings: Codable, Identifiable {
        let id: String
        let name: String
        let current: Double
        let target: Double?          // nil = open-ended accumulation
        let currency: String
        let colorHex: String
        let icon: String
        var hasTarget: Bool { target != nil }
        var fraction: Double {
            guard let t = target, t > 0 else { return 0 }
            return Swift.min(Swift.max(current / t, 0), 1)
        }
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
        language: "fr",
        balances: [BalanceEntry(currency: "CAD", symbol: "$ CA", amount: 0)],
        netWorth: 0, netWorthMonthChange: 0, monthIncome: 0, monthExpense: 0,
        recentTransactions: [], upcoming: [], registeredRooms: [], budgets: [], budgetTransactions: [], accounts: [], accountsTotal: 0, savings: [], updatedAt: .now
    )

    // MARK: - Number formatting

    /// Locale for number grouping, derived from the in-app language (not system).
    private var numberLocale: Locale {
        switch language {
        case "fr": return Locale(identifier: "fr_CA")
        case "es": return Locale(identifier: "es_ES")
        case "pt": return Locale(identifier: "pt_BR")
        default:   return Locale(identifier: "en_CA")
        }
    }

    func formatted(_ amount: Double, currency: String) -> String {
        let sym = balances.first(where: { $0.currency == currency })?.symbol ?? currency
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal
        fmt.locale = numberLocale
        fmt.minimumFractionDigits = 0
        fmt.maximumFractionDigits = 2
        return "\(fmt.string(from: NSNumber(value: amount)) ?? "\(amount)") \(sym)"
    }

    /// Magnitude only (no sign) — for values shown with an explicit +/− prefix.
    func formattedShort(_ amount: Double) -> String {
        let a = Swift.abs(amount)
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal
        fmt.locale = numberLocale
        fmt.maximumFractionDigits = a >= 1_000 ? 0 : 2
        if a >= 1_000_000 { fmt.maximumFractionDigits = 1; return (fmt.string(from: NSNumber(value: a/1_000_000)) ?? "") + "M" }
        if a >= 1_000     { return (fmt.string(from: NSNumber(value: a/1_000)) ?? "") + "k" }
        return fmt.string(from: NSNumber(value: a)) ?? "\(a)"
    }

    /// Signed short value: keeps a minus sign for negatives (balances, net).
    func formattedSigned(_ amount: Double) -> String {
        (amount < 0 ? "−" : "") + formattedShort(amount)
    }

    /// Exact value with grouping, rounded to whole units, no symbol — for hero
    /// numbers where a currency symbol would be shown separately.
    func formattedFull(_ amount: Double) -> String {
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal
        fmt.locale = numberLocale
        fmt.maximumFractionDigits = 0
        return fmt.string(from: NSNumber(value: amount)) ?? "\(Int(amount))"
    }

    /// Full money format: grouped thousands, fixed 2 decimals, currency symbol —
    /// for individual amounts like transactions (uses the amount's own currency).
    func formattedMoney(_ amount: Double, currency: String) -> String {
        let sym = balances.first(where: { $0.currency == currency })?.symbol ?? currency
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal
        fmt.locale = numberLocale
        fmt.minimumFractionDigits = 2
        fmt.maximumFractionDigits = 2
        let n = fmt.string(from: NSNumber(value: amount)) ?? String(format: "%.2f", amount)
        return "\(n) \(sym)"
    }

    // MARK: - Localised widget labels (keyed by in-app language)

    func str(_ key: String) -> String {
        Self.widgetStrings[key]?[language] ?? Self.widgetStrings[key]?["en"] ?? key
    }

    static let widgetStrings: [String: [String: String]] = [
        "balance":    ["fr": "Solde",         "en": "Balance",       "es": "Saldo",          "pt": "Saldo"],
        "balances":   ["fr": "Soldes",        "en": "Balances",      "es": "Saldos",         "pt": "Saldos"],
        "budgets":    ["fr": "Budgets",       "en": "Budgets",       "es": "Presupuestos",   "pt": "Orçamentos"],
        "savings":    ["fr": "Épargne",       "en": "Savings",       "es": "Ahorro",         "pt": "Poupança"],
        "netWorth":   ["fr": "Valeur nette",  "en": "Net Worth",     "es": "Patrimonio",     "pt": "Patrimônio"],
        "thisMonth":  ["fr": "Ce mois",       "en": "This Month",    "es": "Este mes",       "pt": "Este mês"],
        "recent":     ["fr": "Récentes",      "en": "Recent",        "es": "Recientes",      "pt": "Recentes"],
        "upcoming":   ["fr": "À venir",       "en": "Upcoming",      "es": "Próximos",       "pt": "Próximos"],
        "today":      ["fr": "Auj.",          "en": "Today",         "es": "Hoy",            "pt": "Hoje"],
        "available":  ["fr": "dispo.",        "en": "avail.",        "es": "disp.",          "pt": "disp."],
        "room":       ["fr": "Droit de cotisation", "en": "Contribution Room", "es": "Derecho de cotización", "pt": "Direito de contribuição"],
        "income":     ["fr": "Revenus",       "en": "Income",        "es": "Ingresos",       "pt": "Receitas"],
        "expense":    ["fr": "Dépenses",      "en": "Expenses",      "es": "Gastos",         "pt": "Despesas"],
        "over":       ["fr": "Dépassement",   "en": "Over",          "es": "Exceso",         "pt": "Excesso"],
        "noData":     ["fr": "Ouvrez l'app",  "en": "Open the app",  "es": "Abre la app",    "pt": "Abra o app"],
    ]
}
