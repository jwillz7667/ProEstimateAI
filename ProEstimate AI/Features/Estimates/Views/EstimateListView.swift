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
                } else if viewModel.filteredEstimates.isEmpty {
                    emptyState
                } else {
                    estimateList
                }
            }
            .navigationTitle("Estimates")
            .searchable(text: $viewModel.searchText, prompt: "Search estimates...")
            .navigationDestination(for: AppDestination.self) { destination in
                switch destination {
                case .estimateEditor(let id):
                    EstimateEditorView(estimateId: id)
                case .proposalPreview(let id):
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
                // Load both in parallel — projects are needed to enrich summary
                // rows with real project titles.
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

    // MARK: - Subviews

    private var emptyState: some View {
        VStack(spacing: 0) {
            filterPicker
            Spacer()
            EmptyStateView(
                icon: "doc.text",
                title: "No Estimates",
                subtitle: viewModel.searchText.isEmpty
                    ? "Estimates are created inside a project. Open any project to generate or add an estimate."
                    : "No estimates match your search.",
                ctaTitle: viewModel.searchText.isEmpty ? "Go to Projects" : nil,
                ctaAction: viewModel.searchText.isEmpty ? { appState.selectedTab = .projects } : nil
            )
            Spacer()
        }
    }

    private var estimateList: some View {
        VStack(spacing: 0) {
            filterPicker

            ScrollView {
                LazyVStack(spacing: SpacingTokens.sm) {
                    ForEach(viewModel.filteredEstimates) { summary in
                        NavigationLink(value: AppDestination.estimateEditor(id: summary.estimate.id)) {
                            EstimateRowView(summary: summary)
                                .padding(SpacingTokens.md)
                                .glassCard()
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
                .padding(.horizontal, SpacingTokens.md)
                .padding(.vertical, SpacingTokens.xs)
            }
        }
    }

    private var filterPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: SpacingTokens.xs) {
                ForEach(EstimateStatusFilter.allCases) { filter in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.selectedFilter = filter
                        }
                    } label: {
                        Text(filter.title)
                            .font(TypographyTokens.subheadline)
                            .fontWeight(viewModel.selectedFilter == filter ? .semibold : .regular)
                            .padding(.horizontal, SpacingTokens.sm)
                            .padding(.vertical, SpacingTokens.xs)
                            .background(
                                Capsule()
                                    .fill(viewModel.selectedFilter == filter
                                        ? ColorTokens.primaryOrange
                                        : Color.clear)
                            )
                            .foregroundStyle(viewModel.selectedFilter == filter ? .white : .primary)
                    }
                }
            }
            .padding(.horizontal, SpacingTokens.md)
            .padding(.vertical, SpacingTokens.xs)
        }
    }
}

// MARK: - Row View

private struct EstimateRowView: View {
    let summary: EstimateSummary

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xs) {
            HStack {
                Text(summary.estimate.estimateNumber)
                    .font(TypographyTokens.headline)

                if summary.estimate.version > 1 {
                    Text("v\(summary.estimate.version)")
                        .font(TypographyTokens.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, SpacingTokens.xxs)
                        .padding(.vertical, 2)
                        .background(ColorTokens.inputBackground, in: Capsule())
                }

                Spacer()

                StatusBadge(
                    text: summary.estimate.status.rawValue.capitalized,
                    style: statusBadgeStyle(for: summary.estimate.status)
                )
            }

            Text(summary.projectTitle)
                .font(TypographyTokens.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack {
                CurrencyText(amount: summary.estimate.totalAmount, font: TypographyTokens.moneyMedium)

                Spacer()

                Text(summary.estimate.updatedAt.formatted(as: .relative))
                    .font(TypographyTokens.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, SpacingTokens.xxs)
    }

    private func statusBadgeStyle(for status: Estimate.Status) -> StatusBadge.Style {
        switch status {
        case .draft: .neutral
        case .sent: .info
        case .approved: .success
        case .declined: .error
        case .expired: .warning
        }
    }
}

// MARK: - Preview

#Preview {
    EstimateListView()
        .environment(AppRouter())
        .environment(AppState())
}
