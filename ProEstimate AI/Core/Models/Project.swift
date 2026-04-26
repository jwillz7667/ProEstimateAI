import Foundation

/// Represents a remodel or construction project.
/// Projects are the central entity in the app — they link photos, AI generations,
/// estimates, proposals, and invoices into one coherent workflow.
struct Project: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let companyId: String
    let clientId: String?
    let title: String
    let description: String?
    let projectType: ProjectType
    let status: Status
    let budgetMin: Decimal?
    let budgetMax: Decimal?
    let qualityTier: QualityTier
    let squareFootage: Decimal?
    let dimensions: String?
    let language: String?
    let createdAt: Date
    let updatedAt: Date
    /// Resolves to the project's most recent COMPLETED generation preview, or
    /// the first ORIGINAL asset image if no generation exists. Server-provided
    /// (see backend `projects.dto.ts → thumbnail_url`); nil for new projects.
    let thumbnailURL: URL?

    // MARK: - Nested Enums

    /// The category of remodel or construction work.
    enum ProjectType: String, Codable, CaseIterable, Sendable {
        case kitchen
        case bathroom
        case flooring
        case roofing
        case painting
        case siding
        case roomRemodel = "room_remodel"
        case exterior
        case custom
    }

    /// Tracks the project through the full lifecycle from draft to completion.
    enum Status: String, Codable, CaseIterable, Sendable {
        case draft
        case photosUploaded = "photos_uploaded"
        case generating
        case generationComplete = "generation_complete"
        case estimateCreated = "estimate_created"
        case proposalSent = "proposal_sent"
        case approved
        case declined
        case invoiced
        case completed
        case archived
    }

    /// Material and finish quality tier, affects AI generation and cost estimation.
    enum QualityTier: String, Codable, CaseIterable, Sendable {
        case standard
        case premium
        case luxury
    }

    enum CodingKeys: String, CodingKey {
        case id
        case companyId = "company_id"
        case clientId = "client_id"
        case title
        case description
        case projectType = "project_type"
        case status
        case budgetMin = "budget_min"
        case budgetMax = "budget_max"
        case qualityTier = "quality_tier"
        case squareFootage = "square_footage"
        case dimensions
        case language
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case thumbnailURL = "thumbnail_url"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        companyId = try c.decode(String.self, forKey: .companyId)
        clientId = try c.decodeIfPresent(String.self, forKey: .clientId)
        title = try c.decode(String.self, forKey: .title)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        projectType = try c.decode(ProjectType.self, forKey: .projectType)
        status = try c.decode(Status.self, forKey: .status)
        budgetMin = try c.decodeIfPresent(Decimal.self, forKey: .budgetMin)
        budgetMax = try c.decodeIfPresent(Decimal.self, forKey: .budgetMax)
        qualityTier = try c.decode(QualityTier.self, forKey: .qualityTier)
        squareFootage = try c.decodeIfPresent(Decimal.self, forKey: .squareFootage)
        dimensions = try c.decodeIfPresent(String.self, forKey: .dimensions)
        language = try c.decodeIfPresent(String.self, forKey: .language)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        thumbnailURL = try c.decodeIfPresent(URL.self, forKey: .thumbnailURL)
    }

    init(
        id: String,
        companyId: String,
        clientId: String?,
        title: String,
        description: String?,
        projectType: ProjectType,
        status: Status,
        budgetMin: Decimal?,
        budgetMax: Decimal?,
        qualityTier: QualityTier,
        squareFootage: Decimal?,
        dimensions: String?,
        language: String?,
        createdAt: Date,
        updatedAt: Date,
        thumbnailURL: URL? = nil
    ) {
        self.id = id
        self.companyId = companyId
        self.clientId = clientId
        self.title = title
        self.description = description
        self.projectType = projectType
        self.status = status
        self.budgetMin = budgetMin
        self.budgetMax = budgetMax
        self.qualityTier = qualityTier
        self.squareFootage = squareFootage
        self.dimensions = dimensions
        self.language = language
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.thumbnailURL = thumbnailURL
    }
}

// MARK: - Convenience

extension Project {
    /// Budget range formatted for display, e.g. "$15,000 – $25,000".
    var budgetRangeDisplay: String? {
        guard let min = budgetMin else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        let minStr = formatter.string(from: min as NSDecimalNumber) ?? "\(min)"
        if let max = budgetMax {
            let maxStr = formatter.string(from: max as NSDecimalNumber) ?? "\(max)"
            return "\(minStr) – \(maxStr)"
        }
        return minStr
    }

    /// Whether the project is in a terminal state.
    var isFinalized: Bool {
        switch status {
        case .completed, .archived:
            return true
        default:
            return false
        }
    }

    /// Whether the project has an active AI generation in progress.
    var isGenerating: Bool {
        status == .generating
    }
}

// MARK: - Sample Data

extension Project {
    static let sample = Project(
        id: "p-001",
        companyId: "c-001",
        clientId: "cl-001",
        title: "Kitchen Remodel – Mitchell Residence",
        description: "Full kitchen remodel with new cabinets, countertops, and island.",
        projectType: .kitchen,
        status: .draft,
        budgetMin: 15000,
        budgetMax: 35000,
        qualityTier: .premium,
        squareFootage: 250,
        dimensions: "20x12.5",
        language: "en",
        createdAt: Date(),
        updatedAt: Date()
    )
}
