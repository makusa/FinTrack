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
        didSet { UserDefaults.standard.set(current.rawValue, forKey: "appLanguage") }
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

    /// Infers the best matching AppLanguage from the device preferred languages.
    /// Falls back to French (Régis's default) if nothing matches.
    private static func detectDeviceLanguage() -> AppLanguage {
        for langCode in Locale.preferredLanguages {
            // Locale.preferredLanguages returns tags like "fr-CA", "en-GB", "es-ES", "pt-BR"
            let prefix = String(langCode.prefix(2)).lowercased()
            if let match = AppLanguage.allCases.first(where: { $0.rawValue == prefix }) {
                return match
            }
        }
        return .french  // safe default for Régis
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
