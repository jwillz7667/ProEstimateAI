import Foundation
import Observation

@Observable
final class EstimateListViewModel {
    // MARK: - Dependencies

    private let service: EstimateServiceProtocol
    private let projectService: ProjectServiceProtocol

    // MARK: - State

    var estimates: [EstimateSummary] = []
    var projects: [Project] = []
    var searchText: String = ""
    var selectedFilter: EstimateStatusFilter = .all
    var isLoading: Bool = false
    var errorMessage: String?

    // MARK: - Computed

    /// Filtered and searched estimates for display.
    var filteredEstimates: [EstimateSummary] {
        var result = estimates

        // Apply status filter
        if selectedFilter != .all {
            let matchingStatuses = selectedFilter.matchingStatuses
            result = result.filter { matchingStatuses.contains($0.estimate.status) }
        }

        // Apply search text
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { summary in
                summary.estimate.estimateNumber.lowercased().contains(query)
                    || summary.projectTitle.lowercased().contains(query)
            }
        }

        return result
    }

    /// Count of estimates per status for filter badges.
    var draftCount: Int { estimates.filter { $0.estimate.status == .draft }.count }
    var sentCount: Int { estimates.filter { $0.estimate.status == .sent }.count }
    var approvedCount: Int { estimates.filter { $0.estimate.status == .approved }.count }

    // MARK: - Init

    init(
        service: EstimateServiceProtocol = LiveEstimateService(),
        projectService: ProjectServiceProtocol = LiveProjectService()
    ) {
        self.service = service
        self.projectService = projectService
    }

    // MARK: - Actions

    func loadEstimates() async {
        isLoading = true
        errorMessage = nil
        do {
            let summaries = try await service.listEstimates()
            estimates = enrich(summaries: summaries, with: projects)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func loadProjects() async {
        do {
            projects = try await projectService.listProjects()
            // Re-enrich any already-loaded summaries with real project titles.
            estimates = enrich(summaries: estimates, with: projects)
        } catch {
            // Non-fatal — the list still renders with fallback titles.
        }
    }

    func deleteEstimate(id: String) async {
        do {
            try await service.deleteEstimate(id: id)
            estimates.removeAll { $0.id == id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Private Helpers

    /// Replace each summary's placeholder project title (which the API layer
    /// sets to the project ID) with the real title from the loaded projects.
    private func enrich(summaries: [EstimateSummary], with projects: [Project]) -> [EstimateSummary] {
        guard !projects.isEmpty else { return summaries }
        let titlesById = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0.title) })
        return summaries.map { summary in
            guard let title = titlesById[summary.estimate.projectId] else { return summary }
            return EstimateSummary(estimate: summary.estimate, projectTitle: title)
        }
    }
}
