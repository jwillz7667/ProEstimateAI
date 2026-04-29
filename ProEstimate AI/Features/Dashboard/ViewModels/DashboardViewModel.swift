import Foundation
import Observation

@Observable
final class DashboardViewModel {
    // MARK: - Published state

    var summary: DashboardSummary?
    var recentProjects: [Project] = []
    var projectThumbnails: [String: URL] = [:]
    var isLoading: Bool = false
    var errorMessage: String?

    // MARK: - Computed

    /// Greeting based on time of day.
    func greeting(for name: String) -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        let timeGreeting: String
        switch hour {
        case 0 ..< 12:
            timeGreeting = "Good morning"
        case 12 ..< 17:
            timeGreeting = "Good afternoon"
        default:
            timeGreeting = "Good evening"
        }
        return "\(timeGreeting), \(name.components(separatedBy: " ").first ?? name)"
    }

    /// Formatted revenue string for the metric card.
    var formattedRevenue: String {
        guard let revenue = summary?.revenueThisMonth else { return "$0" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: revenue as NSDecimalNumber) ?? "$0"
    }

    // MARK: - Dependencies

    private let apiClient: APIClientProtocol

    init(apiClient: APIClientProtocol = APIClient.shared) {
        self.apiClient = apiClient
    }

    // MARK: - Actions

    func loadDashboard() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        do {
            async let summaryTask: DashboardSummary = apiClient.request(.getDashboardSummary)
            async let projectsTask: [Project] = apiClient.request(.listProjects(cursor: nil))

            summary = try await summaryTask
            recentProjects = try await projectsTask
            await loadThumbnails(for: recentProjects)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func refresh() async {
        await loadDashboard()
    }

    // MARK: - Thumbnail Loading

    /// Hydrate `projectThumbnails` for every project in the carousel.
    ///
    /// Strategy:
    ///   1. Prefer the server-provided `Project.thumbnailURL` — the backend
    ///      already resolves the most recent COMPLETED generation preview
    ///      (or first ORIGINAL asset) and returns it on the project DTO.
    ///      No extra round-trip required.
    ///   2. For projects whose payload arrives without a thumbnail (legacy
    ///      records, or projects whose generation finished after the list
    ///      query), fall back to `listGenerations` so the carousel still
    ///      shows the freshest preview rather than a blank placeholder.
    private func loadThumbnails(for projects: [Project]) async {
        let visible = Array(projects.prefix(10))
        var resolved: [String: URL] = [:]
        var needsLookup: [Project] = []

        for project in visible {
            if let url = project.thumbnailURL {
                resolved[project.id] = url
            } else {
                needsLookup.append(project)
            }
        }

        if !needsLookup.isEmpty {
            await withTaskGroup(of: (String, URL?).self) { group in
                for project in needsLookup {
                    group.addTask { [apiClient] in
                        do {
                            let generations: [AIGeneration] = try await apiClient.request(
                                .listGenerations(projectId: project.id)
                            )
                            let completed = generations.first { $0.status == .completed }
                            return (project.id, completed?.previewURL)
                        } catch {
                            return (project.id, nil)
                        }
                    }
                }

                for await (projectId, url) in group {
                    if let url {
                        resolved[projectId] = url
                    }
                }
            }
        }

        projectThumbnails = resolved
    }
}
