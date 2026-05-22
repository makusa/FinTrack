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

    /// Format a Decimal using fr_CA locale conventions plus the currency code.
    /// We avoid relying on the OS's notion of which symbol to display because
    /// it can be inconsistent (e.g. for XAF). The code is always shown.
    func format(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "fr_CA")
        formatter.minimumFractionDigits = (code == "JPY" || code == "XAF") ? 0 : 2
        formatter.maximumFractionDigits = (code == "JPY" || code == "XAF") ? 0 : 2
        let nsAmount = NSDecimalNumber(decimal: amount)
        let body = formatter.string(from: nsAmount) ?? "\(amount)"
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
    /// Format a Decimal as currency using the curated list. Uses fr_CA locale.
    func formatted(asCurrency code: String) -> String {
        Currencies.info(for: code).format(self)
    }
}
