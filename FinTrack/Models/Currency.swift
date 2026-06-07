//
//  Currency.swift
//  FinTrack
//
//  A curated list of currencies relevant to Régis (CAD home + Cameroon corridor)
//  plus the major ones one might encounter. Stored as ISO 4217 codes on Account.
//

import Foundation

struct CurrencyInfo: Identifiable, Hashable {
    let code: String
    let nameFR: String
    let symbol: String

    var id: String { code }

    // MARK: - Formatter cache
    // NumberFormatter initialization is expensive (locale resolution, encodings).
    // We keep one formatter per currency code and reuse it across all calls.
    // Access is always on the MainActor (UI thread) so no locking needed.
    private static var formatterCache: [String: NumberFormatter] = [:]

    private static func cachedFormatter(code: String) -> NumberFormatter {
        let langID = LanguageManager.shared.locale.identifier
        let cacheKey = "\(code)-\(langID)"
        if let cached = formatterCache[cacheKey] { return cached }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = LanguageManager.shared.locale
        let noDecimals = code == "JPY" || code == "XAF" || code == "XOF"
        f.minimumFractionDigits = noDecimals ? 0 : 2
        f.maximumFractionDigits = noDecimals ? 0 : 2
        formatterCache[cacheKey] = f
        return f
    }

    /// Format a Decimal using the app's current language locale plus the currency symbol.
    /// Uses a cached NumberFormatter keyed by (currency code, locale) — safe to call from hot render paths.
    func format(_ amount: Decimal) -> String {
        let f = CurrencyInfo.cachedFormatter(code: code)
        let body = f.string(from: amount as NSDecimalNumber) ?? "\(amount)"
        return "\(body) \(symbol)"
    }
}

enum Currencies {
    /// Pre-loaded list. Régis can pick from these when creating an account.
    /// Order is intentional: Canadian first, then USD, then Euro/Cameroon corridor, then others.
    static let all: [CurrencyInfo] = [
        CurrencyInfo(code: "CAD", nameFR: "Dollar canadien",                 symbol: "$ CA"),
        CurrencyInfo(code: "USD", nameFR: "Dollar américain",                symbol: "$ US"),
        CurrencyInfo(code: "EUR", nameFR: "Euro",                            symbol: "€"),
        CurrencyInfo(code: "XAF", nameFR: "Franc CFA (Afrique centrale)",    symbol: "FCFA"),
        CurrencyInfo(code: "GBP", nameFR: "Livre sterling",                  symbol: "£"),
        CurrencyInfo(code: "CHF", nameFR: "Franc suisse",                    symbol: "CHF"),
        CurrencyInfo(code: "JPY", nameFR: "Yen japonais",                    symbol: "¥"),
        CurrencyInfo(code: "AUD", nameFR: "Dollar australien",               symbol: "$ AU"),
        CurrencyInfo(code: "MAD", nameFR: "Dirham marocain",                 symbol: "DH"),
        CurrencyInfo(code: "XOF", nameFR: "Franc CFA (Afrique de l'Ouest)",  symbol: "FCFA"),
    ]

    static func info(for code: String) -> CurrencyInfo {
        all.first(where: { $0.code == code }) ?? CurrencyInfo(code: code, nameFR: code, symbol: code)
    }

    /// Default currency for a new account. CAD because Régis is in Montréal.
    static let `default` = "CAD"
}

extension Decimal {
    /// Format a Decimal as currency using the curated list. Uses the app's current language locale.
    func formatted(asCurrency code: String) -> String {
        Currencies.info(for: code).format(self)
    }
}
