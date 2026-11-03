import SwiftUI

struct DashboardView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    @Environment(PaywallPresenter.self) private var paywallPresenter
    @Environment(FeatureGateCoordinator.self) private var featureGateCoordinator
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var eventBus = AppEventBus.shared
    @State private var viewModel = DashboardViewModel()
    @State private var showProjectCreation = false
    @State private var showEstimateCreation = false
    @State private var showSettings = false
    @State private var navigateToProjectId: String?
    @State private var navigateAutoGenerate = false

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.dashboardPath) {
            dashboardContent
                .navigationTitle("Home")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        profileToolbarButton
                    }
                }
                .sheet(isPresented: $showSettings) {
                    NavigationStack {
                        SettingsView()
                            .toolbar {
                                ToolbarItem(placement: .topBarLeading) {
                                    Button("Done") { showSettings = false }
                                }
                            }
                    }
                }
                .task(id: workspaceScope) {
                    await viewModel.loadDashboard(scope: workspaceScope)
                }
                .onChange(of: eventBus.paymentEventToken) { _, _ in reload() }
                .onChange(of: eventBus.projectEventToken) { _, _ in reload() }
                .onChange(of: appState.selectedTab) { _, tab in
                    if tab == .dashboard { reload() }
                }
                .onChange(of: router.dashboardPath.count) { previous, current in
                    // Returning from a document can change the next-action
                    // queue even without switching tabs or pulling to refresh.
                    if current < previous { reload() }
                }
                .fullScreenCover(isPresented: $showProjectCreation) {
                    ProjectCreationFlowView { projectId, autoGenerate in
                        navigateToProjectId = projectId
                        navigateAutoGenerate = autoGenerate
                    }
                }
                .fullScreenCover(isPresented: $showEstimateCreation) {
                    EstimateCreationFlowView { projectId in
                        navigateToProjectId = projectId
                        navigateAutoGenerate = false
                        showEstimateCreation = false
                    }
                }
                .onChange(of: showProjectCreation) { wasPresented, isPresented in
                    if wasPresented && !isPresented {
                        reload()
                        navigateToCreatedProject()
                    }
                }
                .onChange(of: showEstimateCreation) { wasPresented, isPresented in
                    if wasPresented && !isPresented {
                        reload()
                        navigateToCreatedProject()
                    }
                }
                .appNavigationDestinations()
        }
    }

    // MARK: - Home

    private var dashboardContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SpacingTokens.xl) {
                greeting
                creationActions
                workspaceSections
            }
            .padding(.horizontal, SpacingTokens.lg)
            .padding(.top, SpacingTokens.sm)
            .padding(.bottom, SpacingTokens.xxl)
            .frame(maxWidth: 1040)
            .frame(maxWidth: .infinity)
        }
        .background(ColorTokens.background)
        .refreshable { await viewModel.loadDashboard(scope: workspaceScope) }
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
            Text(viewModel.greeting(for: appState.currentUser?.fullName ?? ""))
                .font(TypographyTokens.title3)
                .foregroundStyle(ColorTokens.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            if let companyName = appState.currentCompany?.name, !companyName.isEmpty {
                Text(companyName)
                    .font(TypographyTokens.subheadline)
                    .foregroundStyle(ColorTokens.secondaryText)
            }
        }
    }

    private var creationActions: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xs) {
            newEstimateButton
            Button(action: handleCreateProject) {
                Label("New project", systemImage: "folder.badge.plus")
                    .font(TypographyTokens.subheadline.weight(.semibold))
                    .foregroundStyle(ColorTokens.primaryText)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Organize a project with photos and optional AI previews")
            .accessibilityIdentifier("home.newProject")
        }
    }

    private var newEstimateButton: some View {
        Button { showEstimateCreation = true } label: {
            HStack(alignment: .center, spacing: SpacingTokens.md) {
                Image(systemName: "plus")
                    .font(.title2.weight(.semibold))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                    Text("New estimate")
                        .font(TypographyTokens.title3)
                    Text("Choose a client, price the work and send it for approval.")
                        .font(TypographyTokens.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.right")
                    .font(.body.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(ColorTokens.brandDark)
            .padding(SpacingTokens.lg)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            .background(ColorTokens.primaryOrange, in: RoundedRectangle(cornerRadius: RadiusTokens.card))
            .contentShape(RoundedRectangle(cornerRadius: RadiusTokens.card))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("New estimate")
        .accessibilityHint("Create a manual estimate or use optional AI assistance")
        .accessibilityIdentifier("home.newEstimate")
    }

    @ViewBuilder
    private var workspaceSections: some View {
        if dynamicTypeSize.isAccessibilitySize {
            stackedSections
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: SpacingTokens.xl) {
                    workSections.frame(minWidth: 460, maxWidth: .infinity)
                    businessContext.frame(width: 300)
                }
                stackedSections
            }
        }
    }

    private var stackedSections: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xl) {
            workSections
            businessContext
        }
    }

    private var workSections: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xl) {
            DashboardAttentionSection(
                attention: viewModel.attention,
                isLoading: viewModel.isLoadingAttention,
                errorMessage: viewModel.attentionErrorMessage,
                onSelect: openAttention,
                onRetry: reload
            )
            recentWork
        }
    }

    private var recentWork: some View {
        DashboardRecentProjectsSection(
            projects: viewModel.recentProjects,
            isLoading: viewModel.isLoadingProjects,
            hasLoaded: viewModel.hasLoadedProjects,
            errorMessage: viewModel.projectsErrorMessage,
            onSeeAll: { appState.selectedTab = .projects },
            onRetry: reload
        )
    }

    private var businessContext: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.md) {
            if let summary = viewModel.summary {
                DashboardMetricsSection(summary: summary, formattedRevenue: viewModel.formattedRevenue)
            } else if viewModel.isLoadingSummary {
                HStack(spacing: SpacingTokens.xs) {
                    ProgressView()
                    Text("Loading business totals…")
                        .font(TypographyTokens.caption)
                        .foregroundStyle(ColorTokens.secondaryText)
                }
                .padding(.vertical, SpacingTokens.sm)
            }
            if let message = viewModel.summaryErrorMessage {
                VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                    Text(message)
                        .font(TypographyTokens.caption)
                        .foregroundStyle(ColorTokens.secondaryText)
                    Button("Refresh totals", action: reload)
                        .font(TypographyTokens.caption.weight(.semibold))
                        .foregroundStyle(ColorTokens.primaryText)
                        .frame(minHeight: 44)
                        .disabled(viewModel.isLoadingSummary)
                }
            }
            DashboardSubscriptionCard(
                onUpgrade: { paywallPresenter.present(.settingsUpgrade) },
                onManage: { showSettings = true }
            )
        }
    }

    // MARK: - Settings and Data

    private var profileToolbarButton: some View {
        Button { showSettings = true } label: {
            AvatarView(
                name: appState.currentUser?.fullName ?? "",
                imageURL: appState.currentUser?.avatarURL,
                size: 32
            )
            .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open settings")
        .accessibilityHint("Profile, company details and subscription")
    }

    private var workspaceScope: String {
        "\(appState.currentUser?.id ?? "signed-out"):\(appState.currentCompany?.id ?? "no-company")"
    }

    private func reload() {
        let scope = workspaceScope
        Task { await viewModel.loadDashboard(scope: scope) }
    }

    private func handleCreateProject() {
        switch featureGateCoordinator.guardCreateProject() {
        case .allowed: showProjectCreation = true
        case let .blocked(decision): paywallPresenter.present(decision)
        }
    }

    private func openAttention(_ group: DashboardAttentionGroup) {
        switch group.kind {
        case .overdueInvoice:
            router.dashboardPath.append(AppDestination.invoiceDetail(id: group.target.documentId))
        case .draftEstimate, .approvedEstimate:
            router.dashboardPath.append(AppDestination.projectDetail(
                id: group.target.projectId, highlightEstimateId: group.target.documentId
            ))
        case .unansweredProposal, .changesRequested:
            router.dashboardPath.append(AppDestination.projectDetail(
                id: group.target.projectId, highlightProposalId: group.target.documentId
            ))
        }
    }

    private func navigateToCreatedProject() {
        guard let projectId = navigateToProjectId else { return }
        let autoGenerate = navigateAutoGenerate
        navigateToProjectId = nil
        navigateAutoGenerate = false
        // Complete the cover dismissal before pushing on its originating tab.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            router.dashboardPath = NavigationPath()
            router.dashboardPath.append(AppDestination.projectDetail(id: projectId, autoGenerate: autoGenerate))
        }
    }
}
