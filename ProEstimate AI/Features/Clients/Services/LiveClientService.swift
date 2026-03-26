import Foundation

/// Production implementation of `ClientServiceProtocol` that delegates
/// all client CRUD operations to the backend REST API via `APIClient`.
final class LiveClientService: ClientServiceProtocol, Sendable {
    private let apiClient: APIClientProtocol

    init(apiClient: APIClientProtocol = APIClient.shared) {
        self.apiClient = apiClient
    }

    // MARK: - ClientServiceProtocol

    func listClients() async throws -> [Client] {
        try await apiClient.request(.listClients(cursor: nil))
    }

    func getClient(id: String) async throws -> Client {
        try await apiClient.request(.getClient(id: id))
    }

    func createClient(request: CreateClientRequest) async throws -> Client {
        try await apiClient.request(.createClient(body: request))
    }

    func updateClient(id: String, request: UpdateClientRequest) async throws -> Client {
        try await apiClient.request(.updateClient(id: id, body: request))
    }

    func deleteClient(id: String) async throws {
        try await apiClient.request(.deleteClient(id: id)) as Void
    }
}
