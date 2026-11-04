import Foundation

/// Fetches the client's complete history through the tenant-scoped, paginated endpoint.
struct ClientProjectHistoryService: Sendable {
    private let apiClient: any APIClientProtocol

    init(apiClient: any APIClientProtocol = APIClient.shared) {
        self.apiClient = apiClient
    }

    func projects(clientId: String) async throws -> [Project] {
        let projects: [Project] = try await apiClient.requestAllPages {
            .listClientProjects(clientId: clientId, cursor: $0)
        }
        return projects.sorted {
            if $0.updatedAt == $1.updatedAt { return $0.id < $1.id }
            return $0.updatedAt > $1.updatedAt
        }
    }
}
