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
    let taxInclusivePricing: Bool
    let estimatePrefix: String?
    let invoicePrefix: String?
    let proposalPrefix: String?
    let nextEstimateNumber: Int
    let nextInvoiceNumber: Int
    let nextProposalNumber: Int?
    let defaultLanguage: String?
    let timezone: String?
    let websiteUrl: String?
    let taxLabel: String?
    let appearanceMode: String?
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
        case taxInclusivePricing = "tax_inclusive_pricing"
        case estimatePrefix = "estimate_prefix"
        case invoicePrefix = "invoice_prefix"
        case proposalPrefix = "proposal_prefix"
        case nextEstimateNumber = "next_estimate_number"
        case nextInvoiceNumber = "next_invoice_number"
        case nextProposalNumber = "next_proposal_number"
        case defaultLanguage = "default_language"
        case timezone
        case websiteUrl = "website_url"
        case taxLabel = "tax_label"
        case appearanceMode = "appearance_mode"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /// Older API responses (and test fixtures) may omit the newly-added
    /// `tax_inclusive_pricing` and `appearance_mode` keys. Decode defensively
    /// so a missing key is treated as `false` / `nil` rather than failing the
    /// entire response decode.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        phone = try c.decodeIfPresent(String.self, forKey: .phone)
        email = try c.decodeIfPresent(String.self, forKey: .email)
        address = try c.decodeIfPresent(String.self, forKey: .address)
        city = try c.decodeIfPresent(String.self, forKey: .city)
        state = try c.decodeIfPresent(String.self, forKey: .state)
        zip = try c.decodeIfPresent(String.self, forKey: .zip)
        logoURL = try c.decodeIfPresent(URL.self, forKey: .logoURL)
        primaryColor = try c.decodeIfPresent(String.self, forKey: .primaryColor)
        secondaryColor = try c.decodeIfPresent(String.self, forKey: .secondaryColor)
        defaultTaxRate = try c.decodeIfPresent(Decimal.self, forKey: .defaultTaxRate)
        defaultMarkupPercent = try c.decodeIfPresent(Decimal.self, forKey: .defaultMarkupPercent)
        taxInclusivePricing = try c.decodeIfPresent(Bool.self, forKey: .taxInclusivePricing) ?? false
        estimatePrefix = try c.decodeIfPresent(String.self, forKey: .estimatePrefix)
        invoicePrefix = try c.decodeIfPresent(String.self, forKey: .invoicePrefix)
        proposalPrefix = try c.decodeIfPresent(String.self, forKey: .proposalPrefix)
        nextEstimateNumber = try c.decodeIfPresent(Int.self, forKey: .nextEstimateNumber) ?? 1001
        nextInvoiceNumber = try c.decodeIfPresent(Int.self, forKey: .nextInvoiceNumber) ?? 1001
        nextProposalNumber = try c.decodeIfPresent(Int.self, forKey: .nextProposalNumber)
        defaultLanguage = try c.decodeIfPresent(String.self, forKey: .defaultLanguage)
        timezone = try c.decodeIfPresent(String.self, forKey: .timezone)
        websiteUrl = try c.decodeIfPresent(String.self, forKey: .websiteUrl)
        taxLabel = try c.decodeIfPresent(String.self, forKey: .taxLabel)
        appearanceMode = try c.decodeIfPresent(String.self, forKey: .appearanceMode)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
    }

    init(
        id: String,
        name: String,
        phone: String?,
        email: String?,
        address: String?,
        city: String?,
        state: String?,
        zip: String?,
        logoURL: URL?,
        primaryColor: String?,
        secondaryColor: String?,
        defaultTaxRate: Decimal?,
        defaultMarkupPercent: Decimal?,
        taxInclusivePricing: Bool = false,
        estimatePrefix: String?,
        invoicePrefix: String?,
        proposalPrefix: String?,
        nextEstimateNumber: Int,
        nextInvoiceNumber: Int,
        nextProposalNumber: Int?,
        defaultLanguage: String?,
        timezone: String?,
        websiteUrl: String?,
        taxLabel: String?,
        appearanceMode: String? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.phone = phone
        self.email = email
        self.address = address
        self.city = city
        self.state = state
        self.zip = zip
        self.logoURL = logoURL
        self.primaryColor = primaryColor
        self.secondaryColor = secondaryColor
        self.defaultTaxRate = defaultTaxRate
        self.defaultMarkupPercent = defaultMarkupPercent
        self.taxInclusivePricing = taxInclusivePricing
        self.estimatePrefix = estimatePrefix
        self.invoicePrefix = invoicePrefix
        self.proposalPrefix = proposalPrefix
        self.nextEstimateNumber = nextEstimateNumber
        self.nextInvoiceNumber = nextInvoiceNumber
        self.nextProposalNumber = nextProposalNumber
        self.defaultLanguage = defaultLanguage
        self.timezone = timezone
        self.websiteUrl = websiteUrl
        self.taxLabel = taxLabel
        self.appearanceMode = appearanceMode
        self.createdAt = createdAt
        self.updatedAt = updatedAt
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
        proposalPrefix: "PROP",
        nextEstimateNumber: 1001,
        nextInvoiceNumber: 2001,
        nextProposalNumber: 3001,
        defaultLanguage: "en",
        timezone: "America/New_York",
        websiteUrl: nil,
        taxLabel: "Tax",
        createdAt: Date(),
        updatedAt: Date()
    )
}
