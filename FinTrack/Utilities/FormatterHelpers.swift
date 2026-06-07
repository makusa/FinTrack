//
//  FormatterHelpers.swift
//  FinTrack
//
//  Centralises locale-aware formatting so every date and number in the app
//  reflects the language selected by the user, not the system locale.
//
//  All formatters are cached keyed by (style, locale) to avoid the cost of
//  re-creating them on every render pass.
//

import Foundation

// MARK: - Formatter cache

enum FormatterCache {
    static var dateFormatters:     [String: DateFormatter]         = [:]
    static var relativeFormatters: [String: RelativeDateTimeFormatter] = [:]
    static var numberFormatters:   [String: NumberFormatter]       = [:]

    /// Call when the app language changes to force fresh formatters.
    static func invalidate() {
        dateFormatters.removeAll()
        relativeFormatters.removeAll()
        numberFormatters.removeAll()
    }

    static func date(style: DateFormatter.Style,
                     timeStyle: DateFormatter.Style = .none,
                     locale: Locale) -> DateFormatter {
        let key = "\(style.rawValue)-\(timeStyle.rawValue)-\(locale.identifier)"
        if let cached = dateFormatters[key] { return cached }
        let fmt = DateFormatter()
        fmt.locale    = locale
        fmt.dateStyle = style
        fmt.timeStyle = timeStyle
        dateFormatters[key] = fmt
        return fmt
    }

    static func datePattern(_ pattern: String, locale: Locale) -> DateFormatter {
        let key = "pattern-\(pattern)-\(locale.identifier)"
        if let cached = dateFormatters[key] { return cached }
        let fmt = DateFormatter()
        fmt.locale     = locale
        fmt.dateFormat = pattern
        dateFormatters[key] = fmt
        return fmt
    }

    static func relative(locale: Locale) -> RelativeDateTimeFormatter {
        let key = locale.identifier
        if let cached = relativeFormatters[key] { return cached }
        let fmt = RelativeDateTimeFormatter()
        fmt.locale     = locale
        fmt.unitsStyle = .full
        relativeFormatters[key] = fmt
        return fmt
    }

    static func decimal(locale: Locale) -> NumberFormatter {
        let key = "decimal-\(locale.identifier)"
        if let cached = numberFormatters[key] { return cached }
        let fmt = NumberFormatter()
        fmt.numberStyle           = .decimal
        fmt.locale                = locale
        fmt.usesGroupingSeparator = false
        fmt.maximumFractionDigits = 2
        fmt.minimumFractionDigits = 0
        numberFormatters[key] = fmt
        return fmt
    }
}

// MARK: - Date extensions

extension Date {
    private static var appLocale: Locale { LanguageManager.shared.locale }

    /// Short date (Jun 9, 2026 / 9 juin 2026 / 9 jun. 2026)
    func appFormatted() -> String {
        FormatterCache.date(style: .medium, locale: Self.appLocale).string(from: self)
    }

    /// Long date (June 9, 2026 / 9 juin 2026)
    func appFormattedLong() -> String {
        FormatterCache.date(style: .long, locale: Self.appLocale).string(from: self)
    }

    /// Short date + time
    func appFormattedDateTime() -> String {
        FormatterCache.date(style: .medium, timeStyle: .short, locale: Self.appLocale).string(from: self)
    }

    /// Abbreviated date with custom pattern (e.g. "d MMM" → "9 Jun" / "9 juin")
    func appFormattedPattern(_ pattern: String) -> String {
        FormatterCache.datePattern(pattern, locale: Self.appLocale).string(from: self)
    }

    /// Month + year (June 2026 / juin 2026 / junio 2026)
    func appFormattedMonthYear() -> String {
        appFormattedPattern("MMMM yyyy")
    }

    /// Month abbreviation only (Jun / juin / jun)
    func appFormattedMonthAbbrev() -> String {
        appFormattedPattern("MMM")
    }

    /// Day + month abbreviation (Jun 9 / 9 juin / 9 jun)
    func appFormattedDayMonth() -> String {
        appFormattedPattern("d MMM")
    }

    /// Relative ("2 hours ago" / "il y a 2 heures")
    func appFormattedRelative() -> String {
        FormatterCache.relative(locale: Self.appLocale).localizedString(for: self, relativeTo: Date())
    }
}

// MARK: - Decimal text helper (for editable text fields)

extension Decimal {
    /// Format a Decimal to a locale-aware string suitable for display in an editable text field.
    /// Uses no grouping separator (e.g. "1234.56" in EN, "1234,56" in FR).
    var appFormattedForInput: String {
        let fmt = FormatterCache.decimal(locale: LanguageManager.shared.locale)
        return fmt.string(from: NSDecimalNumber(decimal: self)) ?? "\(self)"
    }
}
