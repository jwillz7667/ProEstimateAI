import SwiftUI

enum AppDestination: Hashable {
    // Projects
    case projectDetail(id: String)
    case projectCreation

    // Estimates
    case estimateEditor(id: String)
    case estimateList(projectId: String)

    // Proposals
    case proposalPreview(id: String)

    // Invoices
    case invoiceDetail(id: String)
    case invoicePreview(id: String)

    // Clients
    case clientDetail(id: String)
    case clientForm(id: String?)

    // Settings
    case companyBranding
    case taxSettings
    case numberingSettings
    case pricingProfiles
    case languageSettings
    case subscriptionSettings
    case analytics

    // Commerce
    case paywall(placement: String)
}

@Observable
final class AppRouter {
    var dashboardPath = NavigationPath()
    var projectsPath = NavigationPath()
    var estimatesPath = NavigationPath()
    var invoicesPath = NavigationPath()
    var clientsPath = NavigationPath()
    var settingsPath = NavigationPath()

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
