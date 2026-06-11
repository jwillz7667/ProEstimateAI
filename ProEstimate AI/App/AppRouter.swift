import SwiftUI

enum AppDestination: Hashable {
    // Projects
    /// `highlightGenerationId` lets a deep link (notification tap) open the
    /// detail screen focused on a specific generation's before/after preview
    /// instead of defaulting to the newest one.
    case projectDetail(id: String, autoGenerate: Bool = false, highlightGenerationId: String? = nil)
    case projectCreation

    // Invoices
    case invoiceDetail(id: String)

    // Clients
    case clientDetail(id: String)
    case clientForm(id: String?)

    // Settings
    case companyBranding
    case taxSettings
    case laborSettings
    case numberingSettings
    case languageSettings
    case subscriptionSettings

    /// Commerce
    case paywall(placement: String)

    /// Property Maps
    /// Lawn polygon measurement on a satellite map. `projectId` is
    /// optional — when nil the screen acts as a one-off measurement
    /// tool; when set, the saved area is PATCHed onto the project.
    case lawnMeasurement(projectId: String?, latitude: Double?, longitude: Double?)
    /// Roof scouting against the Google Solar API. `projectId` is
    /// optional for the same reason as above.
    case roofScouting(projectId: String?, address: String?, latitude: Double?, longitude: Double?)
}

@Observable
final class AppRouter {
    var dashboardPath = NavigationPath()
    var projectsPath = NavigationPath()
    var invoicesPath = NavigationPath()
    var clientsPath = NavigationPath()
    var settingsPath = NavigationPath()

    /// Push a destination onto the navigation stack of the tab the user
    /// is currently viewing. Detail screens reachable from more than one
    /// tab (e.g. `ProjectDetailView` opens from both Dashboard and
    /// Projects) must append onto the stack actually on screen —
    /// hardcoding a single path would push onto a hidden tab and the
    /// navigation would silently no-op.
    func push(_ destination: AppDestination, on tab: AppTab) {
        switch tab {
        case .dashboard: dashboardPath.append(destination)
        case .projects: projectsPath.append(destination)
        case .invoices: invoicesPath.append(destination)
        case .clients: clientsPath.append(destination)
        case .settings: settingsPath.append(destination)
        }
    }
}
