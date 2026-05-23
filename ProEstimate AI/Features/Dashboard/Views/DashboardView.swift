import SwiftUI

/// Projects tab home — the screen the screenshot calls "Dashboard".
/// Sections (top to bottom):
///   1. Toolbar: avatar (leading), brand (principal), bell (trailing)
///   2. Greeting "Welcome back, / Hello, {firstName}"
///   3. "Ready to build?" hero card with Start New Vision CTA
///   4. Recent Visions horizontal carousel (Project thumbnails)
///   5. Active Quotes inline list (Draft / Sent / Approved estimates)
struct DashboardView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    @Environment(EntitlementStore.self) private var entitlementStore
    @Environment(UsageMeterStore.self) private var usageMeterStore
    @Environment(PaywallPresenter.self) private var paywallPresenter
    @Environment(FeatureGateCoordinator.self) private var featureGateCoordinator
    @State private var eventBus = AppEventBus.shared
    @State private var viewModel = DashboardViewModel()
    @State private var showProjectCreation = false
    @State private var showQuickGenerate = false
    @State private var navigateToProjectId: String?
    @State private var navigateAutoGenerate: Bool = false

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.projectsPath) {
            Group {
                if viewModel.isLoading && viewModel.summary == nil {
                    LoadingStateView(message: "Loading...")
                } else if let errorMessage = viewModel.errorMessage, viewModel.summary == nil {
                    RetryStateView(message: errorMessage) {
                        Task { await viewModel.loadDashboard() }
                    }
                } else {
                    homeContent
                }
            }
            .background(ColorTokens.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { homeToolbar }
            .task {
                if viewModel.summary == nil {
                    await viewModel.loadDashboard()
                }
            }
            .onChange(of: eventBus.paymentEventToken) { _, _ in
                Task { await viewModel.loadDashboard() }
            }
            .fullScreenCover(isPresented: $showProjectCreation) {
                ProjectCreationFlowView { projectId, autoGenerate in
                    navigateToProjectId = projectId
                    navigateAutoGenerate = autoGenerate
                }
            }
            .fullScreenCover(isPresented: $showQuickGenerate) {
                QuickGenerateView { projectId in
                    navigateToProjectId = projectId
                    navigateAutoGenerate = false
                }
            }
            .onChange(of: showProjectCreation) { wasPresented, isPresented in
                if wasPresented && !isPresented {
                    Task { await viewModel.loadDashboard() }
                    navigateToCreatedProject()
                }
            }
            .onChange(of: showQuickGenerate) { wasPresented, isPresented in
                if wasPresented && !isPresented {
                    Task { await viewModel.loadDashboard() }
                    navigateToCreatedProject()
                }
            }
            .navigationDestination(for: AppDestination.self) { destination in
                switch destination {
                case let .projectDetail(id, autoGenerate):
                    ProjectDetailView(projectId: id, autoGenerateOnOpen: autoGenerate)
                case .projectsList:
                    ProjectListView()
                case let .clientDetail(id):
                    ClientDetailView(clientId: id)
                default:
                    EmptyView()
                }
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var homeToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                appState.selectedTab = .account
            } label: {
                AvatarView(
                    name: appState.currentUser?.fullName ?? "P",
                    imageURL: appState.currentUser?.avatarURL,
                    size: 32
                )
            }
            .accessibilityLabel("Account")
        }

        ToolbarItem(placement: .principal) {
            Text("ProEstimate AI")
                .font(TypographyTokens.cardTitle)
                .foregroundStyle(ColorTokens.textPrimary)
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button {
                appState.selectedTab = .account
            } label: {
                Image(systemName: "bell")
                    .foregroundStyle(ColorTokens.textPrimary)
            }
            .accessibilityLabel("Notifications")
        }
    }

    // MARK: - Home Content

    private var homeContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SpacingTokens.xl) {
                if entitlementStore.hasBillingIssue {
                    BillingIssueBanner()
                        .padding(.horizontal, SpacingTokens.md)
                }

                greetingSection
                    .padding(.horizontal, SpacingTokens.md)

                ProjectsHomeHeroCard(onStartVision: handleStartVision)
                    .padding(.horizontal, SpacingTokens.md)

                DashboardRecentProjectsSection(
                    projects: viewModel.recentProjects,
                    thumbnails: viewModel.projectThumbnails,
                    onSeeAll: {
                        router.projectsPath.append(AppDestination.projectsList)
                    }
                )

                ActiveQuotesSection(
                    quotes: viewModel.activeQuotes,
                    onSelect: openQuote
                )
                .padding(.bottom, SpacingTokens.xxl)
            }
            .padding(.top, SpacingTokens.sm)
        }
        .refreshable {
            await viewModel.refresh()
        }
    }

    private var greetingSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Welcome back,")
                .font(TypographyTokens.subheadline)
                .foregroundStyle(ColorTokens.textSecondary)

            Text("Hello, \(viewModel.firstName(from: appState.currentUser?.fullName ?? ""))")
                .font(TypographyTokens.largeTitle)
                .foregroundStyle(ColorTokens.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Actions

    /// Hero CTA → AI Remodel Studio. Free users get gated through the
    /// usual paywall coordinator before the QuickGenerate cover opens.
    private func handleStartVision() {
        switch featureGateCoordinator.guardGeneratePreview() {
        case .allowed:
            showQuickGenerate = true
        case let .blocked(decision):
            paywallPresenter.present(decision)
        }
    }

    /// Selecting a quote row jumps to the Quotes tab and pushes the
    /// editor onto its NavigationStack so deep navigation lands in the
    /// right place rather than nested in this tab.
    private func openQuote(_ summary: EstimateSummary) {
        appState.selectedTab = .quotes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            router.quotesPath.append(AppDestination.estimateEditor(id: summary.id))
        }
    }

    // MARK: - Post-Creation Navigation

    private func navigateToCreatedProject() {
        guard let projectId = navigateToProjectId else { return }
        let autoGenerate = navigateAutoGenerate
        navigateToProjectId = nil
        navigateAutoGenerate = false
        // Brief delay lets the fullScreenCover dismiss animation finish
        // before pushing onto the NavigationStack — avoids SwiftUI race.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            router.projectsPath = NavigationPath()
            router.projectsPath.append(
                AppDestination.projectDetail(id: projectId, autoGenerate: autoGenerate)
            )
        }
    }
}
