import Foundation

/// Represents a client-facing proposal generated from an estimate.
/// Proposals are shareable via a unique token and support an approval workflow.
/// The hero image is typically the best AI-generated preview from the project.
struct Proposal: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let estimateId: String
    let projectId: String
    let companyId: String
    let proposalNumber: String?
    let title: String?
    let status: Status
    let shareToken: String?
    let heroImageURL: URL?
    let introText: String?
    let scopeOfWork: String?
    let timelineText: String?
    let termsAndConditions: String?
    let footerText: String?
    let clientMessage: String?
    let pdfAssetId: String?
    let sentAt: Date?
    let viewedAt: Date?
    let respondedAt: Date?
    let expiresAt: Date?
    let createdAt: Date

    // MARK: - Nested Enums

    /// Tracks the proposal through the client approval lifecycle.
    enum Status: String, Codable, CaseIterable, Sendable {
        case draft
        case sent
        case viewed
        case approved
        case declined
        case expired
    }

    enum CodingKeys: String, CodingKey {
        case id
        case estimateId = "estimate_id"
        case projectId = "project_id"
        case companyId = "company_id"
        case proposalNumber = "proposal_number"
        case title
        case status
        case shareToken = "share_token"
        case heroImageURL = "hero_image_url"
        case introText = "intro_text"
        case scopeOfWork = "scope_of_work"
        case timelineText = "timeline_text"
        case termsAndConditions = "terms_and_conditions"
        case footerText = "footer_text"
        case clientMessage = "client_message"
        case pdfAssetId = "pdf_asset_id"
        case sentAt = "sent_at"
        case viewedAt = "viewed_at"
        case respondedAt = "responded_at"
        case expiresAt = "expires_at"
        case createdAt = "created_at"
    }
}

// MARK: - Convenience

extension Proposal {
    /// Shareable URL for the client-facing proposal page.
    /// The base lives on the marketing site (`proestimateai.com/proposal/<token>`).
    var shareURL: URL? {
        guard let shareToken else { return nil }
        return AppConstants.proposalShareBaseURL.appendingPathComponent(shareToken)
    }

    /// Whether the proposal is still pending client action.
    var isPending: Bool {
        status == .sent || status == .viewed
    }

    /// Whether the proposal has expired past its expiration date.
    var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt < Date()
    }
}

// MARK: - Sample Data

extension Proposal {
    static let sample = Proposal(
        id: "prop-001",
        estimateId: "e-001",
        projectId: "p-001",
        companyId: "c-001",
        proposalNumber: "PROP-3001",
        title: "Kitchen Remodel Proposal",
        status: .draft,
        shareToken: "abc123def456",
        heroImageURL: URL(string: "https://cdn.proestimate.ai/gen/gen-001.jpg"),
        introText: "Thank you for choosing us for your kitchen renovation.",
        scopeOfWork: "Full demolition, cabinet install, countertops, backsplash, flooring.",
        timelineText: "Estimated 3-4 weeks from start date.",
        termsAndConditions: "50% deposit required. Balance due upon completion.",
        footerText: nil,
        clientMessage: "Hi Sarah, here is your kitchen remodel proposal.",
        pdfAssetId: nil,
        sentAt: nil,
        viewedAt: nil,
        respondedAt: nil,
        expiresAt: Calendar.current.date(byAdding: .day, value: 30, to: Date()),
        createdAt: Date()
    )
}
