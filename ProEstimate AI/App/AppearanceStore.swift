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

/// Holds the current appearance mode. The mode is treated as account-level
/// state — it follows the user across devices via `Company.appearance_mode`
/// — but is also mirrored to UserDefaults so the very first frame after
/// launch (before bootstrap) renders in the user's preferred theme.
@Observable
final class AppearanceStore {
    private static let key = "appearanceMode"

    /// Public read-only mode. Mutate via `setMode(_:apiClient:)` so we can
    /// guarantee a backend round-trip in addition to local persistence.
    private(set) var mode: AppearanceMode

    var colorScheme: ColorScheme? {
        mode.colorScheme
    }

    init() {
        let stored = UserDefaults.standard.integer(forKey: Self.key)
        mode = AppearanceMode(rawValue: stored) ?? .system
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
        UserDefaults.standard.set(newMode.rawValue, forKey: Self.key)
    }
}

private struct AppearanceBody: Encodable, Sendable {
    let appearanceMode: String
}
