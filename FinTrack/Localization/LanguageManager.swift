//
//  LanguageManager.swift
//  FinTrack
//
//  @Observable singleton for runtime language switching without app restart.
//  Views observe changes via @Environment(LanguageManager.self).
//  Enum labels in models use LanguageManager.shared directly.
//

import SwiftUI

// MARK: - Supported languages

enum AppLanguage: String, CaseIterable, Identifiable {
    case french     = "fr"
    case english    = "en"
    case spanish    = "es"
    case portuguese = "pt"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .french:     return "Français"
        case .english:    return "English"
        case .spanish:    return "Español"
        case .portuguese: return "Português (BR)"
        }
    }

    var flag: String {
        switch self {
        case .french:     return "🇫🇷"
        case .english:    return "🇬🇧"
        case .spanish:    return "🇪🇸"
        case .portuguese: return "🇧🇷"
        }
    }

    /// Locale used for date/number formatting in this language.
    var locale: Locale {
        switch self {
        case .french:     return Locale(identifier: "fr_CA")
        case .english:    return Locale(identifier: "en_CA")
        case .spanish:    return Locale(identifier: "es_ES")
        case .portuguese: return Locale(identifier: "pt_BR")
        }
    }
}

// MARK: - Manager

@Observable
final class LanguageManager {

    static let shared = LanguageManager()

    private(set) var current: AppLanguage {
        didSet {
            UserDefaults.standard.set(current.rawValue, forKey: "appLanguage")
            FormatterCache.invalidate()   // refresh all locale-sensitive formatters
        }
    }

    /// The locale to use for date/number formatting throughout the app.
    var locale: Locale { current.locale }

    private init() {
        if let saved = UserDefaults.standard.string(forKey: "appLanguage"),
           let savedLang = AppLanguage(rawValue: saved) {
            // User has previously chosen a language — respect their preference.
            current = savedLang
        } else {
            // First launch: detect from the device locale.
            current = LanguageManager.detectDeviceLanguage()
        }
    }

    /// Infers the best matching AppLanguage from the device's preferred languages.
    ///
    /// Province-aware for Canadian users:
    ///   • fr-CA  (Quebec / Canadian French)  → French
    ///   • en-CA  (all other provinces)       → English
    ///   • es-*   (any Spanish)               → Spanish
    ///   • pt-*   (any Portuguese)            → Portuguese
    ///
    /// Defaults to **English** — ~75 % of Canadian App Store searches are in English.
    /// French is never the silent default; it is only selected when the device
    /// explicitly signals a French preference.
    private static func detectDeviceLanguage() -> AppLanguage {
        for langTag in Locale.preferredLanguages {
            // Normalize separators: "fr_CA" → "fr-CA"
            let tag = langTag.lowercased().replacingOccurrences(of: "_", with: "-")

            // Explicit Canadian French (Quebec) — must check before generic "fr"
            if tag.hasPrefix("fr-ca") { return .french }

            // Explicit Canadian English — any other province
            if tag.hasPrefix("en-ca") { return .english }

            // Other language families
            switch String(tag.prefix(2)) {
            case "fr": return .french
            case "en": return .english
            case "es": return .spanish
            case "pt": return .portuguese
            default:   break
            }
        }

        // Default: English — majority language of the Canadian market.
        return .english
    }

    func setLanguage(_ language: AppLanguage) {
        current = language
    }

    /// Resolve a localization key for the current language.
    /// Falls back to French, then the key itself.
    subscript(key: String) -> String {
        LocalizedStrings.resolve(key: key, language: current.rawValue)
    }

    /// Format string with arguments (wraps String(format:)).
    func f(_ key: String, _ args: CVarArg...) -> String {
        String(format: self[key], arguments: args)
    }
}

// MARK: - SwiftUI helpers

extension View {
    /// Inject LanguageManager into the environment.
    func withLanguageManager() -> some View {
        self.environment(LanguageManager.shared)
    }
}
