import Foundation

/// A client-facing presentation of an estimate. A proposal wraps an estimate
/// with branding, narrative scope, and a shareable approval link, and tracks
/// the client's response (viewed / approved / declined). It is the middle step
/// of the get-paid loop: estimate → proposal → invoice.
struct Proposal: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let estimateId: String
    let projectId: String
    let companyId: String
    let proposalNumber: String?
    let title: String?
    let status: Status
    let shareToken: String?
    let heroImageURLString: String?
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
    var changesRequestedAt: Date? = nil
    var requestedChangesMessage: String? = nil
    var responseMessage: String? = nil
    var documentHash: String? = nil
    var draftReviewToken: String? = nil
    var acceptance: ProposalAcceptance? = nil
    var recipientClientId: String? = nil
    var recipientName: String? = nil
    var recipientEmail: String? = nil
    var recipientMatchesCurrent: Bool? = nil
    var changeOrder: ProposalChangeOrder? = nil

    // MARK: - Nested Enums

    /// Tracks the proposal through its approval lifecycle. Raw values match
    /// the lowercase strings the backend emits.
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
        case heroImageURLString = "hero_image_url"
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
        case changesRequestedAt = "changes_requested_at"
        case requestedChangesMessage = "requested_changes_message"
        case responseMessage = "response_message"
        case documentHash = "document_hash"
        case draftReviewToken = "draft_review_token"
        case acceptance
        case recipientClientId = "recipient_client_id"
        case recipientName = "recipient_name"
        case recipientEmail = "recipient_email"
        case recipientMatchesCurrent = "recipient_matches_current"
        case changeOrder = "change_order"
    }
}

// MARK: - Convenience

extension Proposal {
    /// The client-facing approval URL, assembled from the share token. `nil`
    /// until sending captures the immutable document and activates its token.
    var shareURL: URL? {
        guard status != .draft, let shareToken, !shareToken.isEmpty else { return nil }
        return AppConstants.proposalShareBaseURL.appendingPathComponent(shareToken)
    }

    /// Parsed hero image URL, when the backend supplied a valid one.
    var heroImageURL: URL? {
        guard let heroImageURLString, !heroImageURLString.isEmpty else { return nil }
        return URL(string: heroImageURLString)
    }

    /// Whether the proposal can still be sent to the client.
    var canSend: Bool {
        guard changesRequestedAt == nil else { return false }
        if status == .draft { return true }
        return (status == .sent || status == .viewed) && recipientMatchesCurrent == true
    }

    var isEditableDraft: Bool { status == .draft && sentAt == nil && documentHash == nil }

    func permitsChanges(currentCompanyId: String?, canEdit: Bool) -> Bool {
        canEdit && currentCompanyId == companyId
    }

    /// Whether the client has acted on the proposal (approved or declined).
    var hasResponse: Bool {
        status == .approved || status == .declined
    }

    /// Display title with a sensible fallback when none was set.
    var displayTitle: String {
        if let title, !title.isEmpty { return title }
        if let proposalNumber, !proposalNumber.isEmpty { return proposalNumber }
        return "Proposal"
    }
}

struct ProposalAcceptance: Codable, Hashable, Sendable {
    let signerName: String
    let acceptedAt: Date
    let documentHash: String
    let estimateVersion: Int
    let consentText: String
    let consentVersion: String
    let identityAssurance: String

    enum CodingKeys: String, CodingKey {
        case signerName = "signer_name"
        case acceptedAt = "accepted_at"
        case documentHash = "document_hash"
        case estimateVersion = "estimate_version"
        case consentText = "consent_text"
        case consentVersion = "consent_version"
        case identityAssurance = "identity_assurance"
    }
}

/// The customer-facing comparison belongs to the frozen proposal version.
/// It contains marked-up line totals and never the contractor's base costs.
struct ProposalChangeOrder: Codable, Hashable, Sendable {
    let id: String
    let title: String
    let reason: String
    let baseEstimateNumber: String
    let baseVersion: Int
    let baseDocumentHash: String
    let baseTotal: Decimal
    let newTotal: Decimal
    let changeAmount: Decimal
    let subtotalDelta: Decimal
    let taxDelta: Decimal
    let discountDelta: Decimal
    let billingEffect: String
    let baseScope: Scope

    struct Scope: Codable, Hashable, Sendable {
        let lineItems: [Line]
        let assumptions: String?
        let exclusions: String?
        enum CodingKeys: String, CodingKey { case lineItems = "line_items", assumptions, exclusions }
    }
    struct Line: Codable, Hashable, Sendable {
        let name: String
        let description: String?
        let quantity: Decimal
        let unit: String
        let lineTotal: Decimal
        enum CodingKeys: String, CodingKey { case name, description, quantity, unit; case lineTotal = "line_total" }
    }
    enum CodingKeys: String, CodingKey {
        case id, title, reason
        case baseEstimateNumber = "base_estimate_number", baseVersion = "base_version", baseDocumentHash = "base_document_hash"
        case baseTotal = "base_total", newTotal = "new_total", changeAmount = "change_amount"
        case subtotalDelta = "subtotal_delta", taxDelta = "tax_delta", discountDelta = "discount_delta"
        case billingEffect = "billing_effect", baseScope = "base_scope"
    }
    var billingExplanation: String {
        switch billingEffect {
        case "additional_invoice": "This increase will be billed separately after approval. The revised contract total is not a second bill for the full project."
        case "credit_note": "This reduction will be recorded as a contract credit after approval. A credit is not a cash refund."
        case "included_in_first_invoice": "This change will be included in the first invoice for the revised contract total. It is not a separate payment request."
        case "no_price_change": "This changes the agreed scope without adding a charge."
        default: "Review this change with your contractor before approving."
        }
    }
}

// MARK: - Sample Data

extension Proposal {
    static let sample = Proposal(
        id: "prop-001",
        estimateId: "e-001",
        projectId: "p-001",
        companyId: "c-001",
        proposalNumber: "PROP-1001",
        title: "Kitchen Remodel Proposal",
        status: .sent,
        shareToken: "tok_abc123",
        heroImageURLString: nil,
        introText: "Thank you for the opportunity to transform your kitchen.",
        scopeOfWork: "Full demolition, new cabinets, quartz counters, and tile.",
        timelineText: "Estimated 3–4 weeks from start.",
        termsAndConditions: "50% deposit due at signing.",
        footerText: nil,
        clientMessage: "Looking forward to working with you!",
        pdfAssetId: nil,
        sentAt: Date(),
        viewedAt: nil,
        respondedAt: nil,
        expiresAt: Calendar.current.date(byAdding: .day, value: 30, to: Date()),
        createdAt: Date()
    )
}
