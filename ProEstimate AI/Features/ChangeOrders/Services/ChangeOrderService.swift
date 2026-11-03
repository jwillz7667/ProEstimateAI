import Foundation

struct ChangeOrderService: ChangeOrderServing {
    let apiClient: any APIClientProtocol
    private let sessionId: UUID
    init(apiClient: any APIClientProtocol = APIClient.shared) {
        self.apiClient = apiClient
        sessionId = TokenStore.shared.sessionIdentifier
    }
    func list(projectId: String) async throws -> [ChangeOrder] {
        try requireSession()
        return try await apiClient.requestAllPages { .listChangeOrders(projectId: projectId, cursor: $0) }
    }
    func get(id: String) async throws -> ChangeOrder {
        try requireSession()
        return try await apiClient.request(.getChangeOrder(id: id))
    }
    func create(_ request: CreateChangeOrderRequest) async throws -> ChangeOrder {
        try requireSession()
        return try await apiClient.request(.createChangeOrder(body: request))
    }
    func apply(id: String, request: ApplyChangeOrderRequest) async throws -> ChangeOrder {
        try requireSession()
        return try await apiClient.request(.applyChangeOrder(id: id, body: request))
    }
    private func requireSession() throws {
        try Task.checkCancellation()
        guard TokenStore.shared.sessionIdentifier == sessionId else { throw APIError.unauthorized }
    }
}
