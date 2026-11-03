import Foundation

struct EstimateDeliveryService: EstimateDeliveryServing {
    private let apiClient: any APIClientProtocol

    init(apiClient: any APIClientProtocol = APIClient.shared) { self.apiClient = apiClient }

    func getProject(id: String) async throws -> Project {
        try await apiClient.request(.getProject(id: id))
    }

    func getClient(id: String) async throws -> Client {
        try await apiClient.request(.getClient(id: id))
    }

    func assignClient(projectId: String, clientId: String) async throws -> Project {
        try await apiClient.request(.updateProject(id: projectId, body: EstimateClientAssignment(clientId: clientId)))
    }

    func listProposals(projectId: String) async throws -> [Proposal] {
        try await apiClient.request(.listProposals(projectId: projectId))
    }

    func createProposal(estimateId: String) async throws -> Proposal {
        try await apiClient.request(.createProposal(body: CreateProposalBody(estimateId: estimateId, title: nil, clientMessage: nil)))
    }

    func reviseEstimate(estimateId: String, requestId: String) async throws -> Estimate {
        try await apiClient.request(.reviseEstimate(id: estimateId, body: EstimateRevisionRequest(requestId: requestId)))
    }

    func convertToInvoice(estimateId: String) async throws -> Invoice {
        try await apiClient.request(.convertEstimateToInvoice(estimateId: estimateId, body: ConvertEstimateRequest.faithful))
    }

    func listInvoices(projectId: String) async throws -> [Invoice] {
        try await apiClient.requestAllPages { .listInvoices(projectId: projectId, cursor: $0) }
    }
}

private struct EstimateClientAssignment: Encodable, Sendable {
    let clientId: String
    enum CodingKeys: String, CodingKey { case clientId = "client_id" }
}
