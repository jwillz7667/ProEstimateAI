import Foundation
import Observation

@Observable
final class DashboardViewModel {
    // MARK: - Published state

    var summary: DashboardSummary?
    var recentProjects: [Project] = []
    var projectThumbnails: [String: URL] = [:]
    /// Estimates that are still in flight — Draft / Sent / Approved.
    /// Drives the "Active Quotes" section on the Projects home tab.
    var activeQuotes: [EstimateSummary] = []
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

    /// First name used in the screenshot's "Hello, Alex" line.
    func firstName(from fullName: String) -> String {
        let trimmed = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "there" }
        return trimmed.components(separatedBy: " ").first ?? trimmed
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
    private let estimateService: EstimateServiceProtocol

    init(
        apiClient: APIClientProtocol = APIClient.shared,
        estimateService: EstimateServiceProtocol = LiveEstimateService()
    ) {
        self.apiClient = apiClient
        self.estimateService = estimateService
    }

    // MARK: - Actions

    func loadDashboard() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        do {
            async let summaryTask: DashboardSummary = apiClient.request(.getDashboardSummary)
            async let projectsTask: [Project] = apiClient.request(.listProjects(cursor: nil))
            async let estimatesTask: [EstimateSummary] = estimateService.listEstimates()

            summary = try await summaryTask
            recentProjects = try await projectsTask
            let allEstimates = (try? await estimatesTask) ?? []
            activeQuotes = pickActive(allEstimates, projects: recentProjects)
            await loadThumbnails(for: recentProjects)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func refresh() async {
        await loadDashboard()
    }

    // MARK: - Quote Filtering

    /// Active = Draft + Sent + Approved. Sorted newest first, capped at 5.
    /// Project titles are spliced in from the freshly loaded project list so
    /// quote cards don't show raw IDs.
    private func pickActive(_ summaries: [EstimateSummary], projects: [Project]) -> [EstimateSummary] {
        let titlesById = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0.title) })
        return summaries
            .filter { [Estimate.Status.draft, .sent, .approved].contains($0.estimate.status) }
            .sorted { $0.estimate.updatedAt > $1.estimate.updatedAt }
            .prefix(5)
            .map { summary in
                guard let title = titlesById[summary.estimate.projectId] else { return summary }
                return EstimateSummary(estimate: summary.estimate, projectTitle: title)
            }
    }

    // MARK: - Thumbnail Loading

    private func loadThumbnails(for projects: [Project]) async {
        await withTaskGroup(of: (String, URL?).self) { group in
            for project in projects.prefix(8) {
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
                    projectThumbnails[projectId] = url
                }
            }
        }
    }
}
