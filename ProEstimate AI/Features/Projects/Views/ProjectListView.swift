import CoreLocation
import SwiftUI

/// Full project list — pushed onto the Projects tab via `AppDestination.projectsList`.
/// Replaces the previous tab-root layout. The parent NavigationStack
/// (owned by `ProjectsHomeView`) handles destination dispatch.
struct ProjectListView: View {
    @State private var viewModel = ProjectListViewModel()
    @State private var showCreation = false
    @State private var navigateToProjectId: String?
    @State private var navigateAutoGenerate: Bool = false
    @Environment(AppRouter.self) private var router
    @Environment(FeatureGateCoordinator.self) private var featureGateCoordinator
    @Environment(PaywallPresenter.self) private var paywallPresenter

    var body: some View {
        @Bindable var router = router
        VStack(spacing: 0) {
            filterBar
                .padding(.horizontal, SpacingTokens.md)
                .padding(.vertical, SpacingTokens.xs)

            contentView
        }
        .background(ColorTokens.background.ignoresSafeArea())
        .navigationTitle("All Projects")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $viewModel.searchText, prompt: "Search projects")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    handleCreateProject()
                } label: {
                    Image(systemName: "plus")
                }
                .tint(ColorTokens.primaryOrange)
                .accessibilityLabel("New project")
                .accessibilityHint("Create a new project")
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
            ProjectCreationFlowView { projectId, autoGenerate in
                navigateToProjectId = projectId
                navigateAutoGenerate = autoGenerate
            }
        }
        .onChange(of: showCreation) { wasPresented, isPresented in
            if wasPresented && !isPresented {
                Task { await viewModel.loadProjects() }
                if let projectId = navigateToProjectId {
                    let autoGenerate = navigateAutoGenerate
                    navigateToProjectId = nil
                    navigateAutoGenerate = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        router.projectsPath.append(
                            AppDestination.projectDetail(id: projectId, autoGenerate: autoGenerate)
                        )
                    }
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
                    handleCreateProject()
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
                            clientName: project.clientId.flatMap { viewModel.clientLookup[$0] },
                            thumbnailURL: project.thumbnailURL
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

    // MARK: - Feature-Gated Actions

    /// Gate the project creation flow. Free users see the paywall instead
    /// of the creation form; subscribed users (and trialing users) skip
    /// straight into the wizard. The backend re-runs the same gate
    /// server-side, so a subscriber who exceeds their monthly cap still
    /// hits the right paywall when they actually create the project.
    private func handleCreateProject() {
        let result = featureGateCoordinator.guardCreateProject()
        switch result {
        case .allowed:
            showCreation = true
        case let .blocked(decision):
            paywallPresenter.present(decision)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ProjectListView()
            .environment(AppRouter())
    }
}
