import SwiftUI

struct EstimateListView: View {
    @State private var viewModel = EstimateListViewModel()
    @State private var showingDeleteConfirmation = false
    @State private var estimateToDelete: String?
    @Environment(AppRouter.self) private var router
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.estimatesPath) {
            Group {
                if viewModel.isLoading && viewModel.estimates.isEmpty {
                    LoadingStateView(message: "Loading estimates...")
                } else if viewModel.estimates.isEmpty {
                    emptyState
                } else {
                    content
                }
            }
            .navigationTitle("Estimates")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SubscriptionBadge()
                }
            }
            .searchable(text: $viewModel.searchText, prompt: "Search estimates...")
            .navigationDestination(for: AppDestination.self) { destination in
                switch destination {
                case let .estimateEditor(id):
                    EstimateEditorView(estimateId: id)
                case let .proposalPreview(id):
                    ProposalPreviewView(proposalId: id)
                default:
                    EmptyView()
                }
            }
            .refreshable {
                await viewModel.loadEstimates()
                await viewModel.loadProjects()
            }
            .task {
                async let estimates: Void = viewModel.loadEstimates()
                async let projects: Void = viewModel.loadProjects()
                _ = await (estimates, projects)
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                }
            }
            .confirmationDialog(
                "Delete Estimate",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let id = estimateToDelete {
                        Task { await viewModel.deleteEstimate(id: id) }
                    }
                }
                Button("Cancel", role: .cancel) {
                    estimateToDelete = nil
                }
            } message: {
                Text("This action cannot be undone.")
            }
        }
    }

    // MARK: - Content

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SpacingTokens.md) {
                estimateList
                    .padding(.horizontal, SpacingTokens.md)

                Color.clear.frame(height: SpacingTokens.xl)
            }
            .padding(.top, SpacingTokens.sm)
        }
    }

    // MARK: - Estimate list

    private var estimateList: some View {
        Group {
            if viewModel.filteredEstimates.isEmpty {
                filteredEmptyView
            } else {
                LazyVStack(spacing: SpacingTokens.sm) {
                    ForEach(viewModel.filteredEstimates) { summary in
                        NavigationLink(value: AppDestination.estimateEditor(id: summary.estimate.id)) {
                            EstimateRowView(summary: summary)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                estimateToDelete = summary.id
                                showingDeleteConfirmation = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
    }

    private var filteredEmptyView: some View {
        VStack(spacing: SpacingTokens.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(ColorTokens.secondaryText)
            Text("No matches")
                .font(TypographyTokens.subheadline)
                .foregroundStyle(ColorTokens.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SpacingTokens.xxl)
    }

    // MARK: - Empty state (no estimates at all)

    private var emptyState: some View {
        EmptyStateView(
            icon: "doc.text",
            title: "No Estimates",
            subtitle: "Estimates are created inside a project. Open any project and tap Generate with AI or Blank Estimate.",
            ctaTitle: "Go to Projects",
            ctaAction: { appState.selectedTab = .projects }
        )
        .padding(.horizontal, SpacingTokens.md)
    }
}

// MARK: - Row View

private struct EstimateRowView: View {
    let summary: EstimateSummary

    var body: some View {
        HStack(spacing: SpacingTokens.sm) {
            // Leading icon block
            Image(systemName: "doc.text")
                .font(.title3)
                .foregroundStyle(ColorTokens.primaryOrange)
                .frame(width: 44, height: 44)
                .background(
                    ColorTokens.primaryOrange.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: RadiusTokens.small)
                )

            VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                HStack(spacing: SpacingTokens.xxs) {
                    Text(summary.estimate.estimateNumber)
                        .font(TypographyTokens.headline)
                        .foregroundStyle(ColorTokens.primaryText)

                    if summary.estimate.version > 1 {
                        Text("v\(summary.estimate.version)")
                            .font(TypographyTokens.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, SpacingTokens.xxs)
                            .padding(.vertical, 1)
                            .background(ColorTokens.inputBackground, in: Capsule())
                    }
                }

                Text(summary.projectTitle)
                    .font(TypographyTokens.caption)
                    .foregroundStyle(ColorTokens.secondaryText)
                    .lineLimit(1)

                HStack(spacing: SpacingTokens.xs) {
                    statusBadge(for: summary.estimate.status)

                    Text("·")
                        .font(TypographyTokens.caption2)
                        .foregroundStyle(.tertiary)

                    Text(summary.estimate.updatedAt.formatted(as: .relative))
                        .font(TypographyTokens.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: SpacingTokens.xxs) {
                CurrencyText(
                    amount: summary.estimate.totalAmount,
                    font: TypographyTokens.moneySmall
                )
                .foregroundStyle(ColorTokens.primaryText)

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(SpacingTokens.md)
        .glassCard()
    }

    private func statusBadge(for status: Estimate.Status) -> some View {
        let (text, color): (String, Color) = {
            switch status {
            case .draft: ("Draft", ColorTokens.secondaryText)
            case .sent: ("Sent", ColorTokens.accentBlue)
            case .approved: ("Approved", ColorTokens.success)
            case .declined: ("Declined", ColorTokens.error)
            case .expired: ("Expired", ColorTokens.warning)
            }
        }()

        return Text(text)
            .font(TypographyTokens.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, SpacingTokens.xs)
            .padding(.vertical, 3)
            .background(color.opacity(0.14), in: Capsule())
            .foregroundStyle(color)
    }
}

// MARK: - Preview

#Preview {
    EstimateListView()
        .environment(AppRouter())
        .environment(AppState())
}
