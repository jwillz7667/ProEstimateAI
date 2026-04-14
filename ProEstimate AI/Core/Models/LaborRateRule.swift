import Foundation

/// Defines an hourly labor rate for a specific work category within a pricing profile.
/// Labor rate rules allow companies to set per-category pricing (e.g., electrical vs plumbing)
/// and enforce minimum hour requirements.
struct LaborRateRule: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let pricingProfileId: String
    let category: String
    let rateType: String
    let ratePerHour: Decimal
    let flatRate: Decimal?
    let unitRate: Decimal?
    let unit: String?
    let minimumHours: Decimal

    enum CodingKeys: String, CodingKey {
        case id
        case pricingProfileId = "pricing_profile_id"
        case category
        case rateType = "rate_type"
        case ratePerHour = "rate_per_hour"
        case flatRate = "flat_rate"
        case unitRate = "unit_rate"
        case unit
        case minimumHours = "minimum_hours"
    }
}

// MARK: - Convenience

extension LaborRateRule {
    /// Minimum charge for this labor category (ratePerHour * minimumHours).
    var minimumCharge: Decimal {
        ratePerHour * minimumHours
    }
}

// MARK: - Sample Data

extension LaborRateRule {
    static let sample = LaborRateRule(
        id: "lrr-001",
        pricingProfileId: "pp-001",
        category: "General Labor",
        rateType: "hourly",
        ratePerHour: 65,
        flatRate: nil,
        unitRate: nil,
        unit: nil,
        minimumHours: 4
    )
}
