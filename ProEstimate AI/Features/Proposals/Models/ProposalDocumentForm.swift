import Foundation

enum ProposalDocumentError: LocalizedError {
    case readOnly
    case invalidResponse
    var errorDescription: String? {
        switch self {
        case .readOnly: "This proposal has already been sent. Create a revision to change its scope or terms."
        case .invalidResponse: "The saved document couldn't be matched to this proposal. Refresh before continuing."
        }
    }
}

struct ProposalDocumentForm: Sendable {
    var title: String
    var introduction: String
    var scope: String
    var timeline: String
    var terms: String
    var message: String
    var footer: String
    var hasExpiration: Bool
    var expiration: Date

    init(proposal: Proposal) {
        title = proposal.title ?? ""
        introduction = proposal.introText ?? ""
        scope = proposal.scopeOfWork ?? ""
        timeline = proposal.timelineText ?? ""
        terms = proposal.termsAndConditions ?? ""
        message = proposal.clientMessage ?? ""
        footer = proposal.footerText ?? ""
        hasExpiration = proposal.expiresAt != nil
        expiration = proposal.expiresAt ?? Date().addingTimeInterval(30 * 86_400)
    }

    func validationMessage(now: Date = Date()) -> String? {
        for (name, value, limit) in [
            ("Title", title, 500), ("Introduction", introduction, 50_000),
            ("Scope", scope, 50_000), ("Timeline", timeline, 50_000),
            ("Terms", terms, 50_000), ("Message", message, 10_000), ("Footer", footer, 50_000),
        ] {
            if value.utf16.count > limit { return "\(name) is too long. Shorten it before saving." }
        }
        if hasExpiration && expiration <= now { return "Choose an expiration date in the future." }
        return nil
    }

    var request: UpdateProposalDocumentBody {
        func optional(_ value: String) -> String? {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return UpdateProposalDocumentBody(
            title: optional(title), introduction: optional(introduction), scope: optional(scope),
            timeline: optional(timeline), terms: optional(terms), message: optional(message),
            footer: optional(footer), expiresAt: hasExpiration ? expiration : nil
        )
    }
}

struct UpdateProposalDocumentBody: Encodable, Sendable {
    let title: String?
    let introduction: String?
    let scope: String?
    let timeline: String?
    let terms: String?
    let message: String?
    let footer: String?
    let expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case title
        case introduction = "intro_text"
        case scope = "scope_of_work"
        case timeline = "timeline_text"
        case terms = "terms_and_conditions"
        case message = "client_message"
        case footer = "footer_text"
        case expiresAt = "expires_at"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(introduction, forKey: .introduction)
        try container.encode(scope, forKey: .scope)
        try container.encode(timeline, forKey: .timeline)
        try container.encode(terms, forKey: .terms)
        try container.encode(message, forKey: .message)
        try container.encode(footer, forKey: .footer)
        if let expiresAt {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            try container.encode(formatter.string(from: expiresAt), forKey: .expiresAt)
        } else {
            try container.encodeNil(forKey: .expiresAt)
        }
    }
}
