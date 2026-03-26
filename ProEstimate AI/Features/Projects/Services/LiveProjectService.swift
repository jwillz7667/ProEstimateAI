import Foundation

/// Production implementation of `ProjectServiceProtocol` that delegates
/// all project CRUD operations to the backend REST API via `APIClient`.
final class LiveProjectService: ProjectServiceProtocol, Sendable {
    private let apiClient: APIClientProtocol

    init(apiClient: APIClientProtocol = APIClient.shared) {
        self.apiClient = apiClient
    }

    // MARK: - ProjectServiceProtocol

    func listProjects() async throws -> [Project] {
        try await apiClient.request(.listProjects(cursor: nil))
    }

    func getProject(id: String) async throws -> Project {
        try await apiClient.request(.getProject(id: id))
    }

    func createProject(request: ProjectCreationRequest) async throws -> Project {
        try await apiClient.request(.createProject(body: request))
    }

    func updateProject(id: String, request: ProjectCreationRequest) async throws -> Project {
        try await apiClient.request(.updateProject(id: id, body: request))
    }

    func deleteProject(id: String) async throws {
        try await apiClient.request(.deleteProject(id: id)) as Void
    }
}
