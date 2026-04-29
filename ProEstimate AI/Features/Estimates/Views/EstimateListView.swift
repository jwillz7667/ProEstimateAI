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
                metricsRow
                    .padding(.horizontal, SpacingTokens.md)

                filterPicker
                    .padding(.bottom, SpacingTokens.xxs)

                estimateList
                    .padding(.horizontal, SpacingTokens.md)

                Color.clear.frame(height: SpacingTokens.xl)
            }
            .padding(.top, SpacingTokens.sm)
        }
    }

    // MARK: - Metrics row

    private var metricsRow: some View {
        HStack(spacing: SpacingTokens.sm) {
            MetricCard(label: "Total", value: formattedTotalValue)
            MetricCard(label: "Drafts", value: "\(viewModel.draftCount)")
            MetricCard(label: "Approved", value: "\(viewModel.approvedCount)")
        }
    }

    private var formattedTotalValue: String {
        let total = viewModel.estimates.reduce(Decimal.zero) { $0 + $1.estimate.totalAmount }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter.string(from: total as NSDecimalNumber) ?? "$0"
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
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 36))
                .foregroundStyle(ColorTokens.secondaryText)
            Text(viewModel.searchText.isEmpty ? "No estimates in \(viewModel.selectedFilter.title.lowercased())" : "No matches")
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

    // MARK: - Filter pills

    private var filterPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: SpacingTokens.xs) {
                ForEach(EstimateStatusFilter.allCases) { filter in
                    FilterPill(
                        title: filter.title,
                        count: count(for: filter),
                        isActive: viewModel.selectedFilter == filter
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.selectedFilter = filter
                        }
                    }
                }
            }
            .padding(.horizontal, SpacingTokens.md)
        }
    }

    private func count(for filter: EstimateStatusFilter) -> Int {
        if filter == .all { return viewModel.estimates.count }
        return viewModel.estimates.filter { filter.matchingStatuses.contains($0.estimate.status) }.count
    }
}

// MARK: - Filter Pill

private struct FilterPill: View {
    let title: String
    let count: Int
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: SpacingTokens.xxs) {
                Text(title)
                    .font(TypographyTokens.subheadline)
                    .fontWeight(isActive ? .semibold : .regular)

                Text("\(count)")
                    .font(TypographyTokens.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, SpacingTokens.xxs)
                    .padding(.vertical, 2)
                    .background(
                        isActive ? Color.white.opacity(0.25) : ColorTokens.primaryOrange.opacity(0.12),
                        in: Capsule()
                    )
            }
            .padding(.horizontal, SpacingTokens.sm)
            .padding(.vertical, SpacingTokens.xs)
            .background(
                Capsule()
                    .fill(isActive ? ColorTokens.primaryOrange : ColorTokens.surface)
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        isActive ? .clear : ColorTokens.primaryOrange.opacity(0.2),
                        lineWidth: 1
                    )
            )
            .foregroundStyle(isActive ? .white : ColorTokens.primaryText)
        }
        .buttonStyle(.plain)
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
