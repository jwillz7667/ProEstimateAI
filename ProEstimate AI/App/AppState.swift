import Foundation
import Observation

@Observable
final class AppState {
    var isAuthenticated: Bool = false
    var currentUser: CurrentUser?
    var currentCompany: CurrentCompany?
    var selectedTab: AppTab = .projects

    struct CurrentUser: Sendable {
        let id: String
        let email: String
        let fullName: String
        let avatarURL: URL?
    }

    /// Lightweight branding snapshot used wherever the full `Company` model
    /// isn't loaded (dashboards, PDF headers, quick status checks). Mirrors
    /// the subset of fields that the estimate/proposal PDFs render.
    struct CurrentCompany: Sendable {
        let id: String
        let name: String
        let phone: String?
        let email: String?
        let addressLines: [String]
        let websiteUrl: String?
        let primaryColorHex: String?
        let logoURL: URL?

        /// Single source of truth for mapping a full `Company` record into
        /// the lightweight snapshot. Composes the multi-line address from
        /// `address` / `city` / `state` / `zip` so PDF consumers can render
        /// it without re-deriving the join.
        static func from(_ company: Company) -> CurrentCompany {
            CurrentCompany(
                id: company.id,
                name: company.name,
                phone: company.phone,
                email: company.email,
                addressLines: composeAddressLines(
                    street: company.address,
                    city: company.city,
                    state: company.state,
                    zip: company.zip
                ),
                websiteUrl: company.websiteUrl,
                primaryColorHex: company.primaryColor,
                logoURL: company.logoURL
            )
        }

        static func composeAddressLines(
            street: String?,
            city: String?,
            state: String?,
            zip: String?
        ) -> [String] {
            var lines: [String] = []
            if let street = street?.trimmingCharacters(in: .whitespaces), !street.isEmpty {
                lines.append(street)
            }
            let cityStateZip = [
                city?.trimmingCharacters(in: .whitespaces),
                [state?.trimmingCharacters(in: .whitespaces), zip?.trimmingCharacters(in: .whitespaces)]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty }
                    .joined(separator: " "),
            ]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
            if !cityStateZip.isEmpty {
                lines.append(cityStateZip)
            }
            return lines
        }
    }

    func signOut(
        entitlementStore: EntitlementStore? = nil,
        usageMeterStore: UsageMeterStore? = nil
    ) {
        TokenStore.shared.clearTokens()
        entitlementStore?.reset()
        usageMeterStore?.reset()
        isAuthenticated = false
        currentUser = nil
        currentCompany = nil
        selectedTab = .projects
    }
}

/// The four primary tabs that anchor the new visual structure:
/// Projects (home), Studio (AI generation), Quotes (unified pipeline),
/// Account (settings + clients + subscription).
enum AppTab: Int, CaseIterable, Identifiable {
    case projects
    case studio
    case quotes
    case account

    var id: Int {
        rawValue
    }

    var title: String {
        switch self {
        case .projects: "Projects"
        case .studio: "Studio"
        case .quotes: "Quotes"
        case .account: "Account"
        }
    }

    var systemImage: String {
        switch self {
        case .projects: "rectangle.grid.2x2.fill"
        case .studio: "sparkles"
        case .quotes: "doc.text.fill"
        case .account: "person.fill"
        }
    }
}
