import SwiftUI

/// Main project list screen displayed under the Projects tab.
/// Provides search, status filtering, pull-to-refresh, and a creation
/// entry point via the toolbar "+" button.
struct ProjectListView: View {
    @State private var viewModel = ProjectListViewModel()
    @State private var showCreation = false
    @State private var navigateToProjectId: String?
    @Environment(AppRouter.self) private var router

    /// Client names are loaded from the API by the view model.

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.projectsPath) {
            VStack(spacing: 0) {
                // Status filter
                filterBar
                    .padding(.horizontal, SpacingTokens.md)
                    .padding(.vertical, SpacingTokens.xs)

                // Content
                contentView
            }
            .navigationTitle("Projects")
            .searchable(text: $viewModel.searchText, prompt: "Search projects")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showCreation = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .tint(ColorTokens.primaryOrange)
                }
            }
            .refreshable {
                await viewModel.loadProjects()
            }
            .task {
                if viewModel.projects.isEmpty {
                    await viewModel.loadProjects()
                }
            }
            .fullScreenCover(isPresented: $showCreation) {
                ProjectCreationFlowView { projectId in
                    navigateToProjectId = projectId
                }
            }
            .onChange(of: showCreation) { wasPresented, isPresented in
                if wasPresented && !isPresented {
                    Task { await viewModel.loadProjects() }
                    if let projectId = navigateToProjectId {
                        navigateToProjectId = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            router.projectsPath = NavigationPath()
                            router.projectsPath.append(AppDestination.projectDetail(id: projectId))
                        }
                    }
                }
            }
            .navigationDestination(for: AppDestination.self) { destination in
                switch destination {
                case .projectDetail(let id):
                    ProjectDetailView(projectId: id)
                case .clientDetail(let id):
                    ClientDetailView(clientId: id)
                default:
                    EmptyView()
                }
            }
        }
    }

    // MARK: - Subviews

    private var filterBar: some View {
        Picker("Filter", selection: $viewModel.selectedFilter) {
            ForEach(ProjectStatusFilter.allCases) { filter in
                Text(filter.title).tag(filter)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var contentView: some View {
        if viewModel.isLoading && viewModel.projects.isEmpty {
            LoadingStateView(message: "Loading projects...")
        } else if let error = viewModel.errorMessage, viewModel.projects.isEmpty {
            RetryStateView(message: error) {
                Task { await viewModel.loadProjects() }
            }
        } else if viewModel.filteredProjects.isEmpty {
            emptyState
        } else {
            projectList
        }
    }

    private var emptyState: some View {
        Group {
            if viewModel.searchText.isEmpty && viewModel.selectedFilter == .all {
                EmptyStateView(
                    icon: "folder.badge.plus",
                    title: "No Projects Yet",
                    subtitle: "Create your first project to start generating AI remodel previews and estimates.",
                    ctaTitle: "New Project"
                ) {
                    showCreation = true
                }
            } else {
                EmptyStateView(
                    icon: "magnifyingglass",
                    title: "No Matching Projects",
                    subtitle: "Try adjusting your search or filter criteria."
                )
            }
        }
    }

    private var projectList: some View {
        ScrollView {
            LazyVStack(spacing: SpacingTokens.sm) {
                ForEach(viewModel.filteredProjects) { project in
                    NavigationLink(value: AppDestination.projectDetail(id: project.id)) {
                        ProjectRowView(
                            project: project,
                            clientName: project.clientId.flatMap { viewModel.clientLookup[$0] }
                        )
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            Task { await viewModel.deleteProject(id: project.id) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.horizontal, SpacingTokens.md)
            .padding(.vertical, SpacingTokens.xs)
        }
    }
}

// MARK: - Preview

#Preview {
    ProjectListView()
        .environment(AppRouter())
}
