import Foundation

/// Represents a contractor company or business entity.
/// Every user belongs to exactly one company. Company-level settings
/// control branding, tax defaults, and document numbering sequences.
struct Company: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let phone: String?
    let email: String?
    let address: String?
    let city: String?
    let state: String?
    let zip: String?
    let logoURL: URL?
    let primaryColor: String?
    let secondaryColor: String?
    let defaultTaxRate: Decimal?
    let defaultMarkupPercent: Decimal?
    let estimatePrefix: String?
    let invoicePrefix: String?
    let nextEstimateNumber: Int
    let nextInvoiceNumber: Int
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case phone
        case email
        case address
        case city
        case state
        case zip
        case logoURL = "logo_url"
        case primaryColor = "primary_color"
        case secondaryColor = "secondary_color"
        case defaultTaxRate = "default_tax_rate"
        case defaultMarkupPercent = "default_markup_percent"
        case estimatePrefix = "estimate_prefix"
        case invoicePrefix = "invoice_prefix"
        case nextEstimateNumber = "next_estimate_number"
        case nextInvoiceNumber = "next_invoice_number"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Sample Data

extension Company {
    /// Sample company for previews and mock data.
    static let sample = Company(
        id: "c-001",
        name: "Apex Remodeling Co.",
        phone: "512-555-0199",
        email: "info@apexremodeling.com",
        address: "1200 Main St",
        city: "Austin",
        state: "TX",
        zip: "78701",
        logoURL: nil,
        primaryColor: "#F97316",
        secondaryColor: "#1E293B",
        defaultTaxRate: 8.25,
        defaultMarkupPercent: 20,
        estimatePrefix: "EST",
        invoicePrefix: "INV",
        nextEstimateNumber: 1001,
        nextInvoiceNumber: 2001,
        createdAt: Date(),
        updatedAt: Date()
    )
}
