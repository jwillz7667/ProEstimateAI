import Foundation

/// Production implementation of `EstimateServiceProtocol` that delegates
/// all estimate CRUD and line-item operations to the backend REST API via `APIClient`.
final class LiveEstimateService: EstimateServiceProtocol, Sendable {
    private let apiClient: APIClientProtocol

    init(apiClient: APIClientProtocol = APIClient.shared) {
        self.apiClient = apiClient
    }

    // MARK: - EstimateServiceProtocol

    func listByProject(projectId: String) async throws -> [Estimate] {
        try await apiClient.request(.listEstimates(projectId: projectId))
    }

    func listByClient(clientId: String) async throws -> [Estimate] {
        try await apiClient.request(.listEstimates(projectId: nil, clientId: clientId))
    }

    func getEstimate(id: String) async throws -> Estimate {
        try await apiClient.request(.getEstimate(id: id))
    }

    func getLineItems(estimateId: String) async throws -> [EstimateLineItem] {
        try await apiClient.request(.listEstimateLineItems(estimateId: estimateId))
    }

    func createEstimate(_ estimate: Estimate) async throws -> Estimate {
        try await apiClient.request(.createEstimate(body: estimate))
    }

    func updateEstimate(_ estimate: Estimate) async throws -> Estimate {
        try await apiClient.request(.updateEstimate(id: estimate.id, body: estimate))
    }

    func deleteEstimate(id: String) async throws {
        try await apiClient.request(.deleteEstimate(id: id)) as Void
    }

    func saveLineItems(_ items: [EstimateLineItem], estimateId: String) async throws -> [EstimateLineItem] {
        guard !items.isEmpty else { return [] }
        // A single transaction prevents a failed upload from leaving half an estimate.
        return try await apiClient.request(
            .batchCreateEstimateLineItems(estimateId: estimateId, body: EstimateLineItemsBatch(items: items))
        )
    }
}

struct EstimateLineItemsBatch: Encodable, Sendable {
    let items: [EstimateLineItem]
}
