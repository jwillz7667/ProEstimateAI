import SwiftUI

struct DashboardView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    @Environment(EntitlementStore.self) private var entitlementStore
    @Environment(UsageMeterStore.self) private var usageMeterStore
    @Environment(PaywallPresenter.self) private var paywallPresenter
    @State private var viewModel = DashboardViewModel()
    @State private var showProjectCreation = false
    @State private var showQuickGenerate = false
    @State private var showClientForm = false
    @State private var navigateToProjectId: String?

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
            .navigationTitle("Dashboard")
            .task {
                if viewModel.summary == nil {
                    await viewModel.loadDashboard()
                }
            }
            .fullScreenCover(isPresented: $showProjectCreation) {
                ProjectCreationFlowView { projectId in
                    navigateToProjectId = projectId
                }
            }
            .fullScreenCover(isPresented: $showQuickGenerate) {
                QuickGenerateView { projectId in
                    navigateToProjectId = projectId
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
                case .projectDetail(let id):
                    ProjectDetailView(projectId: id)
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
                // MARK: - Greeting
                greetingSection
                    .padding(.horizontal, SpacingTokens.md)

                // MARK: - Quick AI Generate (Hero CTA)
                quickGenerateCard
                    .padding(.horizontal, SpacingTokens.md)

                // MARK: - New Project CTA
                SecondaryButton(title: "New Project", icon: "plus.circle.fill") {
                    showProjectCreation = true
                }
                .padding(.horizontal, SpacingTokens.md)

                // MARK: - Metrics Grid
                metricsGrid
                    .padding(.horizontal, SpacingTokens.md)

                // MARK: - Quick Actions
                DashboardQuickActionsSection { action in
                    handleQuickAction(action)
                }

                // MARK: - Recent Projects
                DashboardRecentProjectsSection(
                    projects: viewModel.recentProjects,
                    thumbnails: viewModel.projectThumbnails,
                    onSeeAll: {
                        appState.selectedTab = .projects
                    }
                )

                // MARK: - Subscription Card
                DashboardSubscriptionCard(
                    generationsRemaining: entitlementStore.hasProAccess
                        ? Int.max
                        : usageMeterStore.generationsRemaining,
                    quotesRemaining: entitlementStore.hasProAccess
                        ? Int.max
                        : usageMeterStore.quotesRemaining,
                    isPro: entitlementStore.hasProAccess,
                    onUpgrade: {
                        paywallPresenter.present(.settingsUpgrade)
                    }
                )
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
        HStack(spacing: SpacingTokens.sm) {
            Image("housd-icon-light")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 40)

            VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                Text(viewModel.greeting(for: appState.currentUser?.fullName ?? ""))
                    .font(TypographyTokens.title2)

                if let companyName = appState.currentCompany?.name {
                    Text(companyName)
                        .font(TypographyTokens.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
    }

    // MARK: - Metrics Grid

    private var metricsGrid: some View {
        let summary = viewModel.summary ?? DashboardSummary.empty
        return LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: SpacingTokens.sm),
                GridItem(.flexible(), spacing: SpacingTokens.sm),
            ],
            spacing: SpacingTokens.sm
        ) {
            MetricCard(
                label: "Active Projects",
                value: "\(summary.activeProjectsCount)"
            )

            MetricCard(
                label: "Pending Estimates",
                value: "\(summary.pendingEstimatesCount)"
            )

            MetricCard(
                label: "Revenue This Month",
                value: viewModel.formattedRevenue
            )

            MetricCard(
                label: "Invoices Due",
                value: "\(summary.invoicesDueCount)"
            )
        }
    }

    // MARK: - Quick Generate Card

    private var quickGenerateCard: some View {
        Button {
            showQuickGenerate = true
        } label: {
            HStack(spacing: SpacingTokens.md) {
                // Icon
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

                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 24))
                        .foregroundStyle(.white)
                }

                // Text
                VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                    HStack(spacing: SpacingTokens.xs) {
                        Text("AI Remodel Preview")
                            .font(TypographyTokens.headline)
                            .foregroundStyle(ColorTokens.primaryText)

                        if !entitlementStore.hasProAccess {
                            Text("\(usageMeterStore.generationsRemaining) left")
                                .font(TypographyTokens.caption2)
                                .fontWeight(.semibold)
                                .padding(.horizontal, SpacingTokens.xs)
                                .padding(.vertical, 2)
                                .background(
                                    usageMeterStore.generationsRemaining <= 2
                                        ? ColorTokens.warning.opacity(0.15)
                                        : ColorTokens.primaryOrange.opacity(0.12),
                                    in: Capsule()
                                )
                                .foregroundStyle(
                                    usageMeterStore.generationsRemaining <= 2
                                        ? ColorTokens.warning
                                        : ColorTokens.primaryOrange
                                )
                        }
                    }

                    Text("Upload a photo and see your remodel in seconds")
                        .font(TypographyTokens.caption)
                        .foregroundStyle(ColorTokens.secondaryText)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
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

    // MARK: - Post-Creation Navigation

    private func navigateToCreatedProject() {
        guard let projectId = navigateToProjectId else { return }
        navigateToProjectId = nil
        // Brief delay lets the fullScreenCover dismiss animation finish
        // before pushing onto the NavigationStack — avoids SwiftUI race.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            router.dashboardPath.append(AppDestination.projectDetail(id: projectId))
        }
    }

    // MARK: - Quick Action Handler

    private func handleQuickAction(_ action: QuickAction) {
        switch action {
        case .newProject:
            showProjectCreation = true
        case .newClient:
            showClientForm = true
        case .viewEstimates:
            appState.selectedTab = .estimates
        case .viewInvoices:
            appState.selectedTab = .invoices
        }
    }
}
