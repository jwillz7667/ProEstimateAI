import Foundation

struct DashboardService: DashboardDataProviding {
    private let apiClient: APIClientProtocol

    init(apiClient: APIClientProtocol = APIClient.shared) {
        self.apiClient = apiClient
    }

    func fetchSummary() async throws -> DashboardSummary {
        try await apiClient.request(.getDashboardSummary)
    }

    func fetchAttention() async throws -> DashboardAttention {
        try await apiClient.request(.getDashboardAttention)
    }

    func fetchProjects() async throws -> [Project] {
        // Home is a preview of the newest project page. The Projects tab owns
        // pagination; loading the entire workspace would delay this screen.
        try await apiClient.request(.listProjects(cursor: nil))
    }
}
