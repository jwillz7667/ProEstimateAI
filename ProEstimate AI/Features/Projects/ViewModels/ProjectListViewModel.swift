import Foundation

/// Drives the project list screen — loads projects, applies search + status
/// filtering, and handles deletion.
@Observable
final class ProjectListViewModel {
    // MARK: - Published State

    var projects: [Project] = []
    var searchText: String = ""
    var selectedFilter: ProjectStatusFilter = .all
    var isLoading: Bool = false
    var errorMessage: String?

    // MARK: - Dependencies

    private let projectService: ProjectServiceProtocol

    // MARK: - Init

    init(projectService: ProjectServiceProtocol = MockProjectService()) {
        self.projectService = projectService
    }

    // MARK: - Computed

    /// Projects filtered by the selected status bucket and search text.
    var filteredProjects: [Project] {
        var result = projects

        // Apply status filter
        if selectedFilter != .all {
            let matching = selectedFilter.matchingStatuses
            result = result.filter { matching.contains($0.status) }
        }

        // Apply search text
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { project in
                project.title.lowercased().contains(query)
                || (project.description?.lowercased().contains(query) ?? false)
                || project.projectType.rawValue.lowercased().contains(query)
            }
        }

        return result
    }

    /// Count of projects matching each filter, used for badge display.
    var activeCount: Int {
        projects.filter { ProjectStatusFilter.active.matchingStatuses.contains($0.status) }.count
    }

    var completedCount: Int {
        projects.filter { $0.status == .completed }.count
    }

    var archivedCount: Int {
        projects.filter { $0.status == .archived }.count
    }

    // MARK: - Actions

    func loadProjects() async {
        isLoading = true
        errorMessage = nil

        do {
            projects = try await projectService.listProjects()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func deleteProject(id: String) async {
        do {
            try await projectService.deleteProject(id: id)
            projects.removeAll { $0.id == id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
