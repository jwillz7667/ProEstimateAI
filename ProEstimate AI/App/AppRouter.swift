import SwiftUI

enum AppDestination: Hashable {
    // Projects
    case projectDetail(id: String, autoGenerate: Bool = false)
    case projectCreation
    /// Full searchable/filterable project list — pushed from the Projects home "View All".
    case projectsList

    // Estimates / Quotes
    case estimateEditor(id: String)
    case estimateList(projectId: String)

    /// Proposals
    case proposalPreview(id: String)

    // Clients
    /// Full clients list — pushed from the Account tab.
    case clientsList
    case clientDetail(id: String)
    case clientForm(id: String?)

    // Account / Settings
    case companyBranding
    case taxSettings
    case numberingSettings
    case pricingProfiles
    case languageSettings
    case subscriptionSettings
    case analytics

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
    /// Projects tab navigation (home → project detail → editors).
    var projectsPath = NavigationPath()
    /// Studio tab navigation (AI Remodel Studio → result push).
    var studioPath = NavigationPath()
    /// Quotes tab navigation (quote list → quote editor → proposal preview).
    var quotesPath = NavigationPath()
    /// Account tab navigation (settings sub-screens, clients, subscription).
    var accountPath = NavigationPath()

    /// Legacy single path — unused, kept for compile compatibility.
    var path = NavigationPath()

    func navigate(to destination: AppDestination) {
        path.append(destination)
    }

    func pop() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    func popToRoot() {
        path = NavigationPath()
    }
}
