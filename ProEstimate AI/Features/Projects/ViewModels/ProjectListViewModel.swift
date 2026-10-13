import Foundation

/// Drives the project list screen — loads projects, applies search + status
/// filtering, and handles deletion.
@MainActor
@Observable
final class ProjectListViewModel {
    // MARK: - Published State

    var projects: [Project] = []
    var clientLookup: [String: String] = [:]
    /// Resolved thumbnail URL per project ID. Populated after the list
    /// loads so the row can show the latest AI generation preview (or
    /// the first original asset) without a per-row round-trip.
    var projectThumbnails: [String: URL] = [:]
    var searchText: String = ""
    var selectedFilter: ProjectStatusFilter = .all
    var isLoading: Bool = false
    var errorMessage: String?
    var actionError: String?
    var deletingProjectIDs: Set<String> = []

    // MARK: - Dependencies

    private let projectService: ProjectServiceProtocol
    private let clientService: ClientServiceProtocol
    private let apiClient: APIClientProtocol

    // MARK: - Init

    init(
        projectService: ProjectServiceProtocol = LiveProjectService(),
        clientService: ClientServiceProtocol = LiveClientService(),
        apiClient: APIClientProtocol = APIClient.shared
    ) {
        self.projectService = projectService
        self.clientService = clientService
        self.apiClient = apiClient
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
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            result = result.filter { project in
                project.title.localizedCaseInsensitiveContains(query)
                || (project.description?.localizedCaseInsensitiveContains(query) ?? false)
                || project.projectType.displayName.localizedCaseInsensitiveContains(query)
                || (project.clientId.flatMap { clientLookup[$0] }?.localizedCaseInsensitiveContains(query) ?? false)
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
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            async let projectsTask = projectService.listProjects()
            async let clientsTask = clientService.listClients()

            projects = try await projectsTask
            // Client labels are supplemental. Preserve projects even if a
            // separate client request fails during an otherwise good refresh.
            if let clients = try? await clientsTask {
                clientLookup = Dictionary(clients.map { ($0.id, $0.name) }, uniquingKeysWith: { _, newest in newest })
            }
            await loadThumbnails(for: projects)
        } catch {
            if !Task.isCancelled { errorMessage = error.localizedDescription }
        }
    }

    func deleteProject(id: String) async {
        guard deletingProjectIDs.insert(id).inserted else { return }
        actionError = nil
        defer { deletingProjectIDs.remove(id) }
        do {
            try await projectService.deleteProject(id: id)
            GenerationLifecycleCoordinator.shared.cancel(projectId: id)
            projects.removeAll { $0.id == id }
            projectThumbnails.removeValue(forKey: id)
        } catch {
            actionError = error.localizedDescription
        }
    }

    // MARK: - Thumbnail Loading

    /// Hydrate `projectThumbnails` for each project in the list.
    ///
    /// Strategy mirrors `DashboardViewModel.loadThumbnails`:
    ///   1. Prefer the server-resolved `Project.thumbnailURL` — the
    ///      backend already picks the most recent COMPLETED generation
    ///      preview (or first ORIGINAL asset) and includes it in the
    ///      list payload, so no extra round-trip is needed.
    ///   2. For projects whose payload arrives without a thumbnail
    ///      (legacy records, or projects whose generation completed
    ///      after the list query), fall back to `listGenerations` and
    ///      use the freshest completed preview.
    private func loadThumbnails(for projects: [Project]) async {
        var resolved: [String: URL] = [:]
        var needsLookup: [Project] = []

        for project in projects {
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
