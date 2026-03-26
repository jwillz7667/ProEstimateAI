import Foundation

/// Production implementation of `ProposalServiceProtocol` that delegates
/// all proposal operations to the backend REST API via `APIClient`.
final class LiveProposalService: ProposalServiceProtocol, Sendable {
    private let apiClient: APIClientProtocol

    init(apiClient: APIClientProtocol = APIClient.shared) {
        self.apiClient = apiClient
    }

    // MARK: - ProposalServiceProtocol

    func listProposals() async throws -> [Proposal] {
        try await apiClient.request(.listProposals(projectId: nil))
    }

    func getProposal(id: String) async throws -> Proposal {
        try await apiClient.request(.getProposal(id: id))
    }

    func getProposalEstimate(proposalId: String) async throws -> Estimate {
        // The protocol caller passes the proposalId. We fetch the proposal
        // first to obtain its estimateId, then fetch the full estimate.
        let proposal: Proposal = try await apiClient.request(.getProposal(id: proposalId))
        return try await apiClient.request(.getEstimate(id: proposal.estimateId))
    }

    func getProposalLineItems(estimateId: String) async throws -> [EstimateLineItem] {
        try await apiClient.request(.listEstimateLineItems(estimateId: estimateId))
    }

    func getProposalProject(projectId: String) async throws -> Project {
        try await apiClient.request(.getProject(id: projectId))
    }

    func getProposalClient(clientId: String) async throws -> Client {
        try await apiClient.request(.getClient(id: clientId))
    }

    func getProposalCompany(companyId: String) async throws -> Company {
        // The API returns the company for the authenticated user via /companies/me.
        // The companyId parameter is accepted for protocol conformance but not used
        // in the request path.
        try await apiClient.request(.getCompany)
    }

    func generateFromEstimate(estimateId: String) async throws -> Proposal {
        let body = GenerateProposalBody(estimateId: estimateId)
        return try await apiClient.request(.createProposal(body: body))
    }

    func createProposal(_ proposal: Proposal) async throws -> Proposal {
        try await apiClient.request(.createProposal(body: proposal))
    }

    func updateProposal(_ proposal: Proposal) async throws -> Proposal {
        // The backend does not currently expose a PATCH /proposals/:id endpoint.
        // Until it is available, throw an explicit error so callers know this path
        // is unsupported rather than silently failing.
        throw APIError.unknown("Updating proposals is not yet supported by the API.")
    }

    func deleteProposal(id: String) async throws {
        // The backend does not currently expose a DELETE /proposals/:id endpoint.
        throw APIError.unknown("Deleting proposals is not yet supported by the API.")
    }

    func sendProposal(id: String) async throws -> Proposal {
        try await apiClient.request(.sendProposal(id: id))
    }
}

// MARK: - Request Bodies

/// Body for generating a proposal from an existing estimate.
/// The encoder uses `.convertToSnakeCase`, so `estimateId` becomes `"estimate_id"`.
private struct GenerateProposalBody: Encodable, Sendable {
    let estimateId: String
}
