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
    @State private var showClientForm = false
    @State private var showSettings = false
    @State private var navigateToProjectId: String?
    @State private var navigateAutoGenerate: Bool = false
    @Environment(\.colorScheme) private var colorScheme

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
                    profileToolbarButton
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
            .onChange(of: eventBus.paymentEventToken) { _, _ in
                Task { await viewModel.loadDashboard() }
            }
            .fullScreenCover(isPresented: $showProjectCreation) {
                ProjectCreationFlowView { projectId, autoGenerate in
                    navigateToProjectId = projectId
                    navigateAutoGenerate = autoGenerate
                }
            }
            .onChange(of: showProjectCreation) { wasPresented, isPresented in
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

    // MARK: - Profile / Settings Trigger

    private var profileToolbarButton: some View {
        Button {
            showSettings = true
        } label: {
            AvatarView(
                name: appState.currentUser?.fullName ?? "",
                imageURL: appState.currentUser?.avatarURL,
                size: 32
            )
            .overlay(
                Circle().strokeBorder(ColorTokens.primaryOrange.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open settings")
        .accessibilityHint("Includes profile, branding, billing and app preferences")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Dashboard Content

    private var dashboardContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SpacingTokens.lg) {
                // Billing-issue banner takes precedence — it's a blocking
                // signal the user needs to act on before anything else.
                if entitlementStore.hasBillingIssue {
                    BillingIssueBanner()
                        .padding(.horizontal, SpacingTokens.md)
                }

                DashboardHeroVideoCard()
                    .padding(.horizontal, SpacingTokens.md)

                greetingSection
                    .padding(.horizontal, SpacingTokens.md)

                // Primary CTA — directly under the greeting so the
                // first scannable action on every dashboard load is
                // "start something new".
                newProjectBanner
                    .padding(.horizontal, SpacingTokens.md)

                DashboardRecentProjectsSection(
                    projects: viewModel.recentProjects,
                    thumbnails: viewModel.projectThumbnails,
                    onSeeAll: {
                        appState.selectedTab = .projects
                    },
                    onCreateProject: {
                        handleCreateProject()
                    }
                )
                .padding(.bottom, SpacingTokens.xxl)
            }
            .padding(.top, SpacingTokens.sm)
        }
        .refreshable {
            await viewModel.refresh()
        }
    }

    // MARK: - New Project Banner

    private var newProjectBanner: some View {
        Button {
            handleCreateProject()
        } label: {
            HStack(spacing: SpacingTokens.md) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.18))
                        .frame(width: 52, height: 52)

                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(ColorTokens.primaryText)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("New Project")
                        .font(TypographyTokens.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(ColorTokens.primaryText)

                    Text("Start a new renovation, estimate or invoice")
                        .font(TypographyTokens.caption)
                        .foregroundStyle(ColorTokens.secondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: SpacingTokens.xs)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ColorTokens.secondaryText)
            }
            .padding(.vertical, SpacingTokens.md)
            .padding(.horizontal, SpacingTokens.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [
                        ColorTokens.primaryOrange,
                        ColorTokens.primaryOrange.opacity(0.78),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: RadiusTokens.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: RadiusTokens.card)
                    .strokeBorder(
                        colorScheme == .light ? ColorTokens.primaryText : Color.clear,
                        lineWidth: colorScheme == .light ? 2 : 0
                    )
            )
            .shadow(color: ColorTokens.primaryOrange.opacity(0.32), radius: 16, x: 0, y: 8)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("New Project")
        .accessibilityHint("Starts a new renovation, estimate or invoice")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Greeting

    private var greetingSection: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
            Text(viewModel.greeting(for: appState.currentUser?.fullName ?? ""))
                .font(TypographyTokens.title2)

            if let companyName = appState.currentCompany?.name {
                Text(companyName)
                    .font(TypographyTokens.subheadline)
                    .foregroundStyle(ColorTokens.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Feature-Gated Actions

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
        // before pushing onto the NavigationStack — avoids a SwiftUI race
        // where the push gets eaten mid-dismiss.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            router.dashboardPath = NavigationPath()
            router.dashboardPath.append(
                AppDestination.projectDetail(id: projectId, autoGenerate: autoGenerate)
            )
        }
    }
}
