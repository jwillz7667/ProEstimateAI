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
        // Create each line item individually via the API.
        // The backend assigns IDs and computes line totals.
        var savedItems: [EstimateLineItem] = []
        for item in items {
            let saved: EstimateLineItem = try await apiClient.request(
                .createEstimateLineItem(estimateId: estimateId, body: item)
            )
            savedItems.append(saved)
        }
        return savedItems
    }
}
