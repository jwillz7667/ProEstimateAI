import CoreLocation
import SwiftUI

/// Main project list screen displayed under the Projects tab.
/// Provides search, status filtering, pull-to-refresh, and a creation
/// entry point via the toolbar "+" button.
struct ProjectListView: View {
    @State private var viewModel = ProjectListViewModel()
    @State private var showCreation = false
    @State private var navigateToProjectId: String?
    @State private var navigateAutoGenerate: Bool = false
    @Environment(AppRouter.self) private var router
    @Environment(FeatureGateCoordinator.self) private var featureGateCoordinator
    @Environment(PaywallPresenter.self) private var paywallPresenter

    // Client names are loaded from the API by the view model.

    var body: some View {
        @Bindable var router = router
        // NavigationSplitView auto-collapses to a single stack on compact
        // size classes (iPhone) and shows side-by-side on regular (iPad).
        NavigationSplitView {
            sidebar(router: router)
        } detail: {
            NavigationStack(path: $router.projectsPath) {
                emptyDetailPlaceholder
                    .navigationDestination(for: AppDestination.self) { destination in
                        switch destination {
                        case let .projectDetail(id, autoGenerate):
                            ProjectDetailView(projectId: id, autoGenerateOnOpen: autoGenerate)
                        case let .clientDetail(id):
                            ClientDetailView(clientId: id)
                        case let .lawnMeasurement(projectId, lat, lng):
                            LawnMeasurementView(
                                viewModel: LawnMeasurementViewModel(
                                    projectId: projectId,
                                    initialCenter: (lat != nil && lng != nil)
                                        ? CLLocationCoordinate2D(latitude: lat!, longitude: lng!)
                                        : nil
                                )
                            )
                        case let .roofScouting(projectId, address, lat, lng):
                            RoofScoutingView(
                                viewModel: RoofScoutingViewModel(
                                    projectId: projectId,
                                    initialAddress: address,
                                    initialCoordinate: (lat != nil && lng != nil)
                                        ? CLLocationCoordinate2D(latitude: lat!, longitude: lng!)
                                        : nil
                                )
                            )
                        default:
                            EmptyView()
                        }
                    }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    // MARK: - Sidebar

    private func sidebar(router: AppRouter) -> some View {
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
                        router.projectsPath = NavigationPath()
                        router.projectsPath.append(
                            AppDestination.projectDetail(id: projectId, autoGenerate: autoGenerate)
                        )
                    }
                }
            }
        }
    }

    // MARK: - iPad Empty Detail

    private var emptyDetailPlaceholder: some View {
        VStack(spacing: SpacingTokens.md) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 56, weight: .regular))
                .foregroundStyle(ColorTokens.primaryOrange.opacity(0.55))
                .accessibilityHidden(true)

            Text("Select a Project")
                .font(TypographyTokens.title3)
                .foregroundStyle(ColorTokens.primaryText)

            Text("Pick a project from the list to see its photos, AI previews, and estimates.")
                .font(TypographyTokens.subheadline)
                .foregroundStyle(ColorTokens.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .padding(SpacingTokens.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    ProjectListView()
        .environment(AppRouter())
}
