import Foundation

/// Represents a user within a company.
/// Role determines access level for company-wide resources.
/// The backend is the source of truth for user identity and permissions.
struct User: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let companyId: String
    let email: String
    let fullName: String
    let role: Role
    let avatarURL: URL?
    let phone: String?
    let isActive: Bool
    let createdAt: Date

    // MARK: - Nested Enums

    /// Access role within a company. Determines what actions a user can perform.
    enum Role: String, Codable, CaseIterable, Sendable {
        case owner
        case admin
        case estimator
        case viewer
    }

    enum CodingKeys: String, CodingKey {
        case id
        case companyId = "company_id"
        case email
        case fullName = "full_name"
        case role
        case avatarURL = "avatar_url"
        case phone
        case isActive = "is_active"
        case createdAt = "created_at"
    }
}

// MARK: - Convenience

extension User {
    /// Whether this user can modify estimates, proposals, and invoices.
    var canEdit: Bool {
        switch role {
        case .owner, .admin, .estimator:
            return true
        case .viewer:
            return false
        }
    }

    /// Whether this user has administrative privileges.
    var isAdmin: Bool {
        role == .owner || role == .admin
    }
}

// MARK: - Sample Data

extension User {
    static let sample = User(
        id: "u-001",
        companyId: "c-001",
        email: "mike@apexremodeling.com",
        fullName: "Mike Torres",
        role: .owner,
        avatarURL: nil,
        phone: "512-555-0199",
        isActive: true,
        createdAt: Date()
    )
}
