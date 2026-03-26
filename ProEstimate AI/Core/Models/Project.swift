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
