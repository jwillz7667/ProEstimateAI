import SwiftUI

enum AppearanceMode: Int, CaseIterable {
    case system = 0
    case light = 1
    case dark = 2

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var icon: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    /// Stable string used in API payloads and the `Company.appearance_mode`
    /// column. Decoupled from `rawValue` so renumbering the enum can never
    /// silently break persisted values.
    var persistenceValue: String {
        switch self {
        case .system: "system"
        case .light: "light"
        case .dark: "dark"
        }
    }

    init?(stringValue: String) {
        switch stringValue {
        case "system": self = .system
        case "light": self = .light
        case "dark": self = .dark
        default: return nil
        }
    }
}

/// Holds the current appearance mode and the user's preferred app
/// interface language. Both are treated as account-level state — they
/// follow the user across devices via `Company.appearance_mode` /
/// `Company.default_language` — but are also mirrored to UserDefaults so
/// the very first frame after launch (before bootstrap) renders in the
/// user's preferred theme and locale.
@Observable
final class AppearanceStore {
    private static let modeKey = "appearanceMode"
    private static let languageKey = "appLanguage"

    /// Public read-only mode. Mutate via `setMode(_:apiClient:)` so we can
    /// guarantee a backend round-trip in addition to local persistence.
    private(set) var mode: AppearanceMode

    /// Public read-only interface language. Mutate via `setLanguage(_:)`.
    /// Document-level language (estimates / proposals / invoices) is
    /// persisted separately via `SettingsViewModel.saveLanguageImmediately`,
    /// so toggling here drives the SwiftUI app interface only.
    private(set) var language: AppLanguage

    var colorScheme: ColorScheme? {
        mode.colorScheme
    }

    /// Locale to push into `\.locale` at the SwiftUI root so localized
    /// strings — including those auto-generated into `Localizable.xcstrings`
    /// — resolve against the user's chosen language without requiring an
    /// app restart or a system-language change in iOS Settings.
    var locale: Locale {
        Locale(identifier: language.rawValue)
    }

    init() {
        let storedMode = UserDefaults.standard.integer(forKey: Self.modeKey)
        mode = AppearanceMode(rawValue: storedMode) ?? .system
        let storedLang = UserDefaults.standard.string(forKey: Self.languageKey)
        language = storedLang.flatMap(AppLanguage.init(rawValue:)) ?? .english
    }

    /// User-driven update. Updates local state immediately for responsiveness,
    /// mirrors to UserDefaults for the next cold launch, and PATCHes the
    /// backend so other devices pick up the change. Network errors are
    /// swallowed — the local change still stands and will reconcile on the
    /// next `loadSettings()` round-trip.
    @MainActor
    func setMode(
        _ newMode: AppearanceMode,
        apiClient: APIClientProtocol? = nil
    ) async {
        applyLocal(newMode)
        let client = apiClient ?? APIClient.shared
        let body = AppearanceBody(appearanceMode: newMode.persistenceValue)
        do {
            let _: Company = try await client.request(.updateCompany(body: body))
        } catch {
            // Swallow — see docstring.
        }
    }

    /// Apply a mode without making a network call. Used by `SettingsViewModel`
    /// when it has just pulled `Company.appearanceMode` from the server and
    /// wants the UI to match without writing back.
    @MainActor
    func applyRemote(mode newMode: AppearanceMode) {
        applyLocal(newMode)
    }

    private func applyLocal(_ newMode: AppearanceMode) {
        guard mode != newMode else { return }
        mode = newMode
        UserDefaults.standard.set(newMode.rawValue, forKey: Self.modeKey)
    }

    // MARK: - Language

    /// Set the active app-interface language. Persists to UserDefaults so
    /// the next cold launch starts in the chosen locale; document-level
    /// language is persisted separately via the backend.
    @MainActor
    func setLanguage(_ newLanguage: AppLanguage) {
        guard language != newLanguage else { return }
        language = newLanguage
        UserDefaults.standard.set(newLanguage.rawValue, forKey: Self.languageKey)
    }

    /// Apply a language without persisting — used when the backend hands
    /// us the saved `Company.defaultLanguage` after sign-in and we want
    /// the UI to match without writing back.
    @MainActor
    func applyRemote(language newLanguage: AppLanguage) {
        guard language != newLanguage else { return }
        language = newLanguage
        UserDefaults.standard.set(newLanguage.rawValue, forKey: Self.languageKey)
    }
}

private struct AppearanceBody: Encodable, Sendable {
    let appearanceMode: String
}
