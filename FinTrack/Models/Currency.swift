//
//  Currency.swift
//  FinTrack
//
//  Catalogue of currencies the user can track. CAD is the home/base currency
//  (Régis is in Montréal); the Cameroon corridor (XAF/XOF) and a broad set of
//  world currencies are included so users can pick the ones relevant to them.
//  Stored as ISO 4217 codes on Account/Budget/Loan/CreditLine/SavingsProject.
//
//  Which of these a user actually *tracks* is governed at runtime by
//  ExchangeRateManager.activeCurrencies (default CAD+USD); this list is just the
//  catalogue to pick from, plus the display metadata (name, symbol, decimals).
//

import Foundation

struct CurrencyInfo: Identifiable, Hashable {
    let code: String
    let nameFR: String
    let symbol: String
    /// ISO 4217 minor units (decimal places). 0 for JPY/XAF/KRW…, 3 for KWD/BHD…
    var minorUnits: Int = 2

    var id: String { code }

    /// Localized display name (FR/EN/ES/PT) via LocalizedStrings ("currency.<CODE>"),
    /// falling back to the French literal for codes without a localized entry.
    var name: String {
        let key = "currency.\(code)"
        let resolved = LanguageManager.shared[key]
        return resolved == key ? nameFR : resolved
    }

    // MARK: - Formatter cache
    // NumberFormatter initialization is expensive (locale resolution, encodings).
    // We keep one formatter per (currency code, locale) and reuse it across calls.
    // Access is always on the MainActor (UI thread) so no locking needed.
    private static var formatterCache: [String: NumberFormatter] = [:]

    private static func cachedFormatter(code: String) -> NumberFormatter {
        let langID = LanguageManager.shared.locale.identifier
        let cacheKey = "\(code)-\(langID)"
        if let cached = formatterCache[cacheKey] { return cached }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = LanguageManager.shared.locale
        let units = Currencies.minorUnits(for: code)
        f.minimumFractionDigits = units
        f.maximumFractionDigits = units
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
    /// Full catalogue the user can pick from. Order: home (CAD), USD, then by region.
    /// `minorUnits` defaults to 2; set explicitly for 0- and 3-decimal currencies.
    static let all: [CurrencyInfo] = [
        // — North America —
        CurrencyInfo(code: "CAD", nameFR: "Dollar canadien",                 symbol: "$ CA"),
        CurrencyInfo(code: "USD", nameFR: "Dollar américain",                symbol: "$ US"),
        CurrencyInfo(code: "MXN", nameFR: "Peso mexicain",                   symbol: "$ MX"),
        // — Europe —
        CurrencyInfo(code: "EUR", nameFR: "Euro",                            symbol: "€"),
        CurrencyInfo(code: "GBP", nameFR: "Livre sterling",                  symbol: "£"),
        CurrencyInfo(code: "CHF", nameFR: "Franc suisse",                    symbol: "CHF"),
        CurrencyInfo(code: "SEK", nameFR: "Couronne suédoise",               symbol: "kr"),
        CurrencyInfo(code: "NOK", nameFR: "Couronne norvégienne",            symbol: "kr"),
        CurrencyInfo(code: "DKK", nameFR: "Couronne danoise",                symbol: "kr"),
        CurrencyInfo(code: "PLN", nameFR: "Zloty polonais",                  symbol: "zł"),
        CurrencyInfo(code: "CZK", nameFR: "Couronne tchèque",                symbol: "Kč"),
        CurrencyInfo(code: "HUF", nameFR: "Forint hongrois",                 symbol: "Ft"),
        CurrencyInfo(code: "RON", nameFR: "Leu roumain",                     symbol: "lei"),
        CurrencyInfo(code: "ISK", nameFR: "Couronne islandaise",             symbol: "kr",   minorUnits: 0),
        CurrencyInfo(code: "TRY", nameFR: "Livre turque",                    symbol: "₺"),
        CurrencyInfo(code: "RUB", nameFR: "Rouble russe",                    symbol: "₽"),
        CurrencyInfo(code: "UAH", nameFR: "Hryvnia ukrainienne",             symbol: "₴"),
        // — Central / West Africa (corridor) —
        CurrencyInfo(code: "XAF", nameFR: "Franc CFA (Afrique centrale)",    symbol: "FCFA", minorUnits: 0),
        CurrencyInfo(code: "XOF", nameFR: "Franc CFA (Afrique de l'Ouest)",  symbol: "FCFA", minorUnits: 0),
        CurrencyInfo(code: "NGN", nameFR: "Naira nigérian",                  symbol: "₦"),
        CurrencyInfo(code: "GHS", nameFR: "Cedi ghanéen",                    symbol: "₵"),
        CurrencyInfo(code: "GNF", nameFR: "Franc guinéen",                   symbol: "FG",   minorUnits: 0),
        CurrencyInfo(code: "CDF", nameFR: "Franc congolais",                 symbol: "FC"),
        // — East / Southern Africa —
        CurrencyInfo(code: "KES", nameFR: "Shilling kényan",                 symbol: "Ksh"),
        CurrencyInfo(code: "UGX", nameFR: "Shilling ougandais",              symbol: "USh",  minorUnits: 0),
        CurrencyInfo(code: "TZS", nameFR: "Shilling tanzanien",              symbol: "TSh"),
        CurrencyInfo(code: "RWF", nameFR: "Franc rwandais",                  symbol: "FRw",  minorUnits: 0),
        CurrencyInfo(code: "ETB", nameFR: "Birr éthiopien",                  symbol: "Br"),
        CurrencyInfo(code: "ZAR", nameFR: "Rand sud-africain",               symbol: "R"),
        CurrencyInfo(code: "ZMW", nameFR: "Kwacha zambien",                  symbol: "ZK"),
        CurrencyInfo(code: "MUR", nameFR: "Roupie mauricienne",              symbol: "₨"),
        // — Maghreb / North Africa —
        CurrencyInfo(code: "MAD", nameFR: "Dirham marocain",                 symbol: "DH"),
        CurrencyInfo(code: "TND", nameFR: "Dinar tunisien",                  symbol: "DT",   minorUnits: 3),
        CurrencyInfo(code: "DZD", nameFR: "Dinar algérien",                  symbol: "DA"),
        CurrencyInfo(code: "EGP", nameFR: "Livre égyptienne",                symbol: "E£"),
        // — Middle East —
        CurrencyInfo(code: "AED", nameFR: "Dirham des Émirats",              symbol: "AED"),
        CurrencyInfo(code: "SAR", nameFR: "Riyal saoudien",                  symbol: "SAR"),
        CurrencyInfo(code: "QAR", nameFR: "Riyal qatari",                    symbol: "QAR"),
        CurrencyInfo(code: "KWD", nameFR: "Dinar koweïtien",                 symbol: "KWD",  minorUnits: 3),
        CurrencyInfo(code: "BHD", nameFR: "Dinar bahreïni",                  symbol: "BHD",  minorUnits: 3),
        CurrencyInfo(code: "OMR", nameFR: "Rial omanais",                    symbol: "OMR",  minorUnits: 3),
        CurrencyInfo(code: "JOD", nameFR: "Dinar jordanien",                 symbol: "JOD",  minorUnits: 3),
        CurrencyInfo(code: "ILS", nameFR: "Shekel israélien",                symbol: "₪"),
        CurrencyInfo(code: "LBP", nameFR: "Livre libanaise",                 symbol: "L£"),
        // — Asia —
        CurrencyInfo(code: "JPY", nameFR: "Yen japonais",                    symbol: "¥",    minorUnits: 0),
        CurrencyInfo(code: "CNY", nameFR: "Yuan chinois",                    symbol: "¥ CN"),
        CurrencyInfo(code: "HKD", nameFR: "Dollar de Hong Kong",             symbol: "$ HK"),
        CurrencyInfo(code: "INR", nameFR: "Roupie indienne",                 symbol: "₹"),
        CurrencyInfo(code: "KRW", nameFR: "Won sud-coréen",                  symbol: "₩",    minorUnits: 0),
        CurrencyInfo(code: "SGD", nameFR: "Dollar de Singapour",             symbol: "$ SG"),
        CurrencyInfo(code: "MYR", nameFR: "Ringgit malaisien",               symbol: "RM"),
        CurrencyInfo(code: "THB", nameFR: "Baht thaïlandais",                symbol: "฿"),
        CurrencyInfo(code: "IDR", nameFR: "Roupie indonésienne",             symbol: "Rp"),
        CurrencyInfo(code: "PHP", nameFR: "Peso philippin",                  symbol: "₱"),
        CurrencyInfo(code: "VND", nameFR: "Dong vietnamien",                 symbol: "₫",    minorUnits: 0),
        CurrencyInfo(code: "PKR", nameFR: "Roupie pakistanaise",             symbol: "₨ Pk"),
        CurrencyInfo(code: "BDT", nameFR: "Taka bangladais",                 symbol: "৳"),
        // — Oceania —
        CurrencyInfo(code: "AUD", nameFR: "Dollar australien",               symbol: "$ AU"),
        CurrencyInfo(code: "NZD", nameFR: "Dollar néo-zélandais",            symbol: "$ NZ"),
        // — Latin America —
        CurrencyInfo(code: "BRL", nameFR: "Real brésilien",                  symbol: "R$"),
        CurrencyInfo(code: "ARS", nameFR: "Peso argentin",                   symbol: "$ AR"),
        CurrencyInfo(code: "CLP", nameFR: "Peso chilien",                    symbol: "$ CL", minorUnits: 0),
        CurrencyInfo(code: "COP", nameFR: "Peso colombien",                  symbol: "$ CO"),
        CurrencyInfo(code: "PEN", nameFR: "Sol péruvien",                    symbol: "S/"),
    ]

    /// O(1)-after-first lookup table by code.
    private static let byCode: [String: CurrencyInfo] =
        Dictionary(uniqueKeysWithValues: all.map { ($0.code, $0) })

    static func info(for code: String) -> CurrencyInfo {
        byCode[code] ?? CurrencyInfo(code: code, nameFR: code, symbol: code)
    }

    /// Minor units (decimals) for a code; 2 if unknown.
    static func minorUnits(for code: String) -> Int {
        byCode[code]?.minorUnits ?? 2
    }

    /// Home/base currency. CAD because Régis is in Montréal; also the FX pivot.
    static let `default` = "CAD"
}

extension Decimal {
    /// Format a Decimal as currency using the catalogue. Uses the app's current language locale.
    func formatted(asCurrency code: String) -> String {
        Currencies.info(for: code).format(self)
    }
}
