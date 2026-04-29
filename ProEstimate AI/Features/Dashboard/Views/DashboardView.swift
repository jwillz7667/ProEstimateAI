import SwiftUI

struct DashboardView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    @Environment(EntitlementStore.self) private var entitlementStore
    @Environment(PaywallPresenter.self) private var paywallPresenter
    @Environment(FeatureGateCoordinator.self) private var featureGateCoordinator
    @State private var eventBus = AppEventBus.shared
    @State private var viewModel = DashboardViewModel()
    @State private var showProjectCreation = false
    @State private var showQuickGenerate = false
    @State private var showClientForm = false
    @State private var showSettings = false
    @State private var navigateToProjectId: String?
    @State private var navigateAutoGenerate: Bool = false

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.dashboardPath) {
            Group {
                if viewModel.isLoading && viewModel.summary == nil {
                    LoadingStateView(message: "Loading dashboard...")
                } else if let errorMessage = viewModel.errorMessage, viewModel.summary == nil {
                    RetryStateView(message: errorMessage) {
                        Task { await viewModel.loadDashboard() }
                    }
                } else {
                    dashboardContent
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SubscriptionBadge()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .foregroundStyle(ColorTokens.primaryOrange)
                    }
                    .accessibilityLabel("Settings")
                    .accessibilityHint("Opens app settings")
                }
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    SettingsView()
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("Done") {
                                    showSettings = false
                                }
                                .foregroundStyle(ColorTokens.primaryOrange)
                            }
                        }
                }
            }
            .task {
                if viewModel.summary == nil {
                    await viewModel.loadDashboard()
                }
            }
            // Reload revenue metrics when an invoice payment event fires
            // from another screen.
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
            .sheet(isPresented: $showClientForm) {
                NavigationStack {
                    ClientFormView()
                }
            }
            .navigationDestination(for: AppDestination.self) { destination in
                switch destination {
                case let .projectDetail(id, autoGenerate):
                    ProjectDetailView(projectId: id, autoGenerateOnOpen: autoGenerate)
                default:
                    EmptyView()
                }
            }
        }
    }

    // MARK: - Dashboard Content

    private var dashboardContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SpacingTokens.lg) {
                // MARK: - Billing issue banner (grace period / retry)

                if entitlementStore.hasBillingIssue {
                    BillingIssueBanner()
                        .padding(.horizontal, SpacingTokens.md)
                }

                // MARK: - Greeting

                greetingSection
                    .padding(.horizontal, SpacingTokens.md)

                // MARK: - Quick AI Generate (Hero CTA)

                quickGenerateCard
                    .padding(.horizontal, SpacingTokens.md)

                // MARK: - New Project CTA

                SecondaryButton(title: "New Project", icon: "plus.circle.fill") {
                    handleCreateProject()
                }
                .padding(.horizontal, SpacingTokens.md)

                // MARK: - Recent Projects

                DashboardRecentProjectsSection(
                    projects: viewModel.recentProjects,
                    thumbnails: viewModel.projectThumbnails,
                    onSeeAll: {
                        appState.selectedTab = .projects
                    }
                )

                // MARK: - Subscription Card

                DashboardSubscriptionCard(onUpgrade: {
                    paywallPresenter.present(.settingsUpgrade)
                })
                .padding(.horizontal, SpacingTokens.md)
                .padding(.bottom, SpacingTokens.xxl)
            }
            .padding(.top, SpacingTokens.sm)
        }
        .refreshable {
            await viewModel.refresh()
        }
    }

    // MARK: - Greeting

    private var greetingSection: some View {
        VStack(spacing: SpacingTokens.sm) {
            ZStack {
                // Always-white circle so the brand icon stays legible in both
                // light and dark mode. (ColorTokens.surface goes near-black in
                // dark mode and made the icon disappear.)
                Circle()
                    .fill(Color.white)
                    .frame(width: 80, height: 80)
                    .shadow(color: ColorTokens.primaryOrange.opacity(0.25), radius: 12, x: 0, y: 4)

                Image("housd-icon-light")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 48, height: 48)
            }

            VStack(spacing: SpacingTokens.xxs) {
                Text(viewModel.greeting(for: appState.currentUser?.fullName ?? ""))
                    .font(TypographyTokens.title2)

                if let companyName = appState.currentCompany?.name {
                    Text(companyName)
                        .font(TypographyTokens.subheadline)
                        .foregroundStyle(ColorTokens.secondaryText)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Quick Generate Card

    private var quickGenerateCard: some View {
        Button {
            handleQuickGenerate()
        } label: {
            HStack(spacing: SpacingTokens.md) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [ColorTokens.primaryOrange, ColorTokens.primaryOrange.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)

                    Image(systemName: entitlementStore.hasProAccess ? "wand.and.stars" : "lock.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                    Text("AI Remodel Preview")
                        .font(TypographyTokens.headline)
                        .foregroundStyle(ColorTokens.primaryText)

                    Text("Upload a photo and see your remodel in seconds")
                        .font(TypographyTokens.caption)
                        .foregroundStyle(ColorTokens.secondaryText)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(ColorTokens.tertiaryText)
            }
            .padding(SpacingTokens.md)
            .background(
                LinearGradient(
                    colors: [
                        ColorTokens.primaryOrange.opacity(0.08),
                        ColorTokens.primaryOrange.opacity(0.03),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: RadiusTokens.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: RadiusTokens.card)
                    .strokeBorder(ColorTokens.primaryOrange.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Feature-Gated Actions

    private func handleQuickGenerate() {
        switch featureGateCoordinator.guardGeneratePreview() {
        case .allowed:
            showQuickGenerate = true
        case let .blocked(decision):
            paywallPresenter.present(decision)
        }
    }

    private func handleCreateProject() {
        switch featureGateCoordinator.guardCreateProject() {
        case .allowed:
            showProjectCreation = true
        case let .blocked(decision):
            paywallPresenter.present(decision)
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
            // Clear any stale navigation entries first so we don't land on an old project
            router.dashboardPath = NavigationPath()
            router.dashboardPath.append(
                AppDestination.projectDetail(id: projectId, autoGenerate: autoGenerate)
            )
        }
    }
}
