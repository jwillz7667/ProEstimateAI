import Foundation
import Observation

@Observable
final class AppState {
    var isAuthenticated: Bool = false
    var currentUser: CurrentUser?
    var currentCompany: CurrentCompany?
    var selectedTab: AppTab = .dashboard

    struct CurrentUser: Sendable {
        let id: String
        let email: String
        let fullName: String
        let avatarURL: URL?
    }

    struct CurrentCompany: Sendable {
        let id: String
        let name: String
        let logoURL: URL?
    }

    func signOut() {
        isAuthenticated = false
        currentUser = nil
        currentCompany = nil
        selectedTab = .dashboard
    }
}

enum AppTab: Int, CaseIterable, Identifiable {
    case dashboard
    case projects
    case estimates
    case invoices
    case clients
    case settings

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .projects: "Projects"
        case .estimates: "Estimates"
        case .invoices: "Invoices"
        case .clients: "Clients"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: "square.grid.2x2"
        case .projects: "folder"
        case .estimates: "doc.text"
        case .invoices: "dollarsign.circle"
        case .clients: "person.2"
        case .settings: "gearshape"
        }
    }
}
