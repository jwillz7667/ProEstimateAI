import Foundation

/// Production implementation of `ProposalServiceProtocol`. Delegates all
/// proposal operations to the backend REST API via `APIClient`.
final class LiveProposalService: ProposalServiceProtocol, Sendable {
    private let apiClient: APIClientProtocol

    init(apiClient: APIClientProtocol = APIClient.shared) {
        self.apiClient = apiClient
    }

    func listByProject(projectId: String) async throws -> [Proposal] {
        try await apiClient.request(.listProposals(projectId: projectId))
    }

    func getProposal(id: String) async throws -> Proposal {
        try await apiClient.request(.getProposal(id: id))
    }

    func createFromEstimate(estimateId: String, title: String?, clientMessage: String?) async throws -> Proposal {
        let body = CreateProposalBody(estimateId: estimateId, title: title, clientMessage: clientMessage)
        return try await apiClient.request(.createProposal(body: body))
    }

    func sendProposal(id: String, clientMessage: String?) async throws -> Proposal {
        let body = SendProposalBody(clientMessage: clientMessage)
        return try await apiClient.request(.sendProposal(id: id, body: body))
    }

    func deleteProposal(id: String) async throws {
        try await apiClient.request(.deleteProposal(id: id)) as Void
    }
}
