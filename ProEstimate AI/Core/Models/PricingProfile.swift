import Foundation

/// Represents a reusable pricing profile for a company.
/// Pricing profiles define default markup, contingency, and waste factors
/// that are applied when generating estimates. A company can have multiple
/// profiles (e.g., "Standard", "Premium") with one marked as default.
struct PricingProfile: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let companyId: String
    let name: String
    let defaultMarkupPercent: Decimal
    let contingencyPercent: Decimal
    let wasteFactor: Decimal
    let isDefault: Bool
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case companyId = "company_id"
        case name
        case defaultMarkupPercent = "default_markup_percent"
        case contingencyPercent = "contingency_percent"
        case wasteFactor = "waste_factor"
        case isDefault = "is_default"
        case createdAt = "created_at"
    }
}

// MARK: - Sample Data

extension PricingProfile {
    static let sample = PricingProfile(
        id: "pp-001",
        companyId: "c-001",
        name: "Standard",
        defaultMarkupPercent: 20,
        contingencyPercent: 10,
        wasteFactor: 1.10,
        isDefault: true,
        createdAt: Date()
    )
}
