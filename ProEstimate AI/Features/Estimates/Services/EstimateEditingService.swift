import Foundation

struct EstimateEditingService: EstimateEditing {
    private let apiClient: APIClientProtocol

    init(apiClient: APIClientProtocol = APIClient.shared) {
        self.apiClient = apiClient
    }

    func getEstimate(id: String) async throws -> Estimate {
        try await apiClient.request(.getEstimate(id: id))
    }

    func getLineItems(estimateId: String) async throws -> [EstimateLineItem] {
        try await apiClient.request(.listEstimateLineItems(estimateId: estimateId))
    }

    func addLineItem(estimateId: String, request: EstimateLineItemEditRequest) async throws {
        let _: EstimateLineItem = try await apiClient.request(.createEstimateLineItem(estimateId: estimateId, body: request))
    }

    func updateLineItem(id: String, request: EstimateLineItemEditRequest) async throws {
        let _: EstimateLineItem = try await apiClient.request(.updateEstimateLineItem(id: id, body: request))
    }

    func removeLineItem(id: String) async throws {
        try await apiClient.request(.deleteEstimateLineItem(id: id)) as Void
    }
}
