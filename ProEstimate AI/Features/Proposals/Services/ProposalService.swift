import Foundation

// MARK: - Protocol

/// Abstracts proposal CRUD + send for the get-paid loop. A proposal wraps an
/// approved estimate in a client-facing, shareable document.
protocol ProposalServiceProtocol: Sendable {
    func listByProject(projectId: String) async throws -> [Proposal]
    func getProposal(id: String) async throws -> Proposal
    /// Create a proposal from an existing estimate. The backend derives the
    /// project, copies branding/defaults, and mints a share token.
    func createFromEstimate(estimateId: String, title: String?, clientMessage: String?) async throws -> Proposal
    /// Send the proposal to the client (status → sent, emails the client).
    func sendProposal(id: String, clientMessage: String?) async throws -> Proposal
    func deleteProposal(id: String) async throws
}

// MARK: - Request Bodies

/// Create-proposal body. Only `estimate_id` is required; the backend derives
/// the rest. Optional fields are omitted (not sent as null) on create.
struct CreateProposalBody: Encodable, Sendable {
    let estimateId: String
    let title: String?
    let clientMessage: String?

    enum CodingKeys: String, CodingKey {
        case estimateId = "estimate_id"
        case title
        case clientMessage = "client_message"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(estimateId, forKey: .estimateId)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encodeIfPresent(clientMessage, forKey: .clientMessage)
    }
}

/// Send-proposal body. Optional message override delivered to the client.
struct SendProposalBody: Encodable, Sendable {
    let clientMessage: String?

    enum CodingKeys: String, CodingKey {
        case clientMessage = "client_message"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(clientMessage, forKey: .clientMessage)
    }
}

// MARK: - Errors

enum ProposalServiceError: LocalizedError {
    case notFound
    case createFailed
    case sendFailed

    var errorDescription: String? {
        switch self {
        case .notFound: "Proposal not found."
        case .createFailed: "Failed to create proposal. Please try again."
        case .sendFailed: "Failed to send proposal. Please try again."
        }
    }
}

// MARK: - Mock Implementation

final class MockProposalService: ProposalServiceProtocol {
    private let simulatedDelay: UInt64 = 400_000_000 // 0.4s

    func listByProject(projectId: String) async throws -> [Proposal] {
        try await Task.sleep(nanoseconds: simulatedDelay)
        return [Proposal.sample].filter { $0.projectId == projectId }
    }

    func getProposal(id: String) async throws -> Proposal {
        try await Task.sleep(nanoseconds: simulatedDelay)
        guard Proposal.sample.id == id else { throw ProposalServiceError.notFound }
        return .sample
    }

    func createFromEstimate(estimateId: String, title: String?, clientMessage _: String?) async throws -> Proposal {
        try await Task.sleep(nanoseconds: simulatedDelay)
        var sample = Proposal.sample
        sample = Proposal(
            id: sample.id,
            estimateId: estimateId,
            projectId: sample.projectId,
            companyId: sample.companyId,
            proposalNumber: sample.proposalNumber,
            title: title ?? sample.title,
            status: .draft,
            shareToken: sample.shareToken,
            heroImageURLString: sample.heroImageURLString,
            introText: sample.introText,
            scopeOfWork: sample.scopeOfWork,
            timelineText: sample.timelineText,
            termsAndConditions: sample.termsAndConditions,
            footerText: sample.footerText,
            clientMessage: sample.clientMessage,
            pdfAssetId: sample.pdfAssetId,
            sentAt: nil,
            viewedAt: nil,
            respondedAt: nil,
            expiresAt: sample.expiresAt,
            createdAt: sample.createdAt
        )
        return sample
    }

    func sendProposal(id _: String, clientMessage _: String?) async throws -> Proposal {
        try await Task.sleep(nanoseconds: simulatedDelay)
        return .sample
    }

    func deleteProposal(id _: String) async throws {
        try await Task.sleep(nanoseconds: simulatedDelay)
    }
}
