import SwiftUI

struct DashboardView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    @Environment(EntitlementStore.self) private var entitlementStore
    @Environment(UsageMeterStore.self) private var usageMeterStore
    @Environment(PaywallPresenter.self) private var paywallPresenter
    @State private var viewModel = DashboardViewModel()

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
        }
    }

    // MARK: - Dashboard Content

    private var dashboardContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SpacingTokens.lg) {
                // MARK: - Greeting
                greetingSection
                    .padding(.horizontal, SpacingTokens.md)

                // MARK: - New Estimate CTA
                PrimaryCTAButton(
                    title: "New Estimate",
                    icon: "plus.circle.fill"
                ) {
                    router.navigate(to: .projectCreation)
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
                    onProjectTap: { project in
                        router.navigate(to: .projectDetail(id: project.id))
                    },
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
            router.navigate(to: .projectCreation)
        case .newClient:
            router.navigate(to: .clientForm(id: nil))
        case .scanReceipt:
            break
        case .viewReports:
            break
        }
    }
}
