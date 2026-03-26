import SwiftUI

struct DashboardView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    @Environment(EntitlementStore.self) private var entitlementStore
    @Environment(UsageMeterStore.self) private var usageMeterStore
    @Environment(PaywallPresenter.self) private var paywallPresenter
    @State private var viewModel = DashboardViewModel()
    @State private var showProjectCreation = false
    @State private var showClientForm = false
    @State private var navigateToProjectId: String?

    var body: some View {
        NavigationStack {
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
                // Refresh dashboard and navigate to newly created project
                Task { await viewModel.loadDashboard() }
                if let projectId = navigateToProjectId {
                    navigateToProjectId = nil
                    router.navigate(to: .projectDetail(id: projectId))
                }
            } content: {
                ProjectCreationFlowView { projectId in
                    navigateToProjectId = projectId
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

                // MARK: - New Project CTA
                PrimaryCTAButton(
                    title: "New Project",
                    icon: "plus.circle.fill"
                ) {
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
        VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
            Text(viewModel.greeting(for: appState.currentUser?.fullName ?? ""))
                .font(TypographyTokens.title2)

            if let companyName = appState.currentCompany?.name {
                Text(companyName)
                    .font(TypographyTokens.subheadline)
                    .foregroundStyle(.secondary)
            }
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

    // MARK: - Quick Action Handler

    private func handleQuickAction(_ action: QuickAction) {
        switch action {
        case .newProject:
            showProjectCreation = true
        case .newClient:
            showClientForm = true
        case .scanReceipt:
            break
        case .viewReports:
            break
        }
    }
}
