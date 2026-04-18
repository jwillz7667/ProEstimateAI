import SwiftUI

struct InvoiceListView: View {
    @State private var viewModel = InvoiceListViewModel()
    @State private var showingDeleteConfirmation = false
    @State private var invoiceToDelete: String?
    @Environment(AppRouter.self) private var router
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.invoicesPath) {
            Group {
                if viewModel.isLoading && viewModel.invoices.isEmpty {
                    LoadingStateView(message: "Loading invoices...")
                } else if viewModel.invoices.isEmpty {
                    emptyState
                } else {
                    content
                }
            }
            .navigationTitle("Invoices")
            .searchable(text: $viewModel.searchText, prompt: "Search invoices...")
            .navigationDestination(for: AppDestination.self) { destination in
                switch destination {
                case .invoicePreview(let id):
                    InvoicePreviewView(invoiceId: id)
                default:
                    EmptyView()
                }
            }
            .refreshable {
                await viewModel.loadInvoices()
            }
            .task {
                await viewModel.loadInvoices()
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                }
            }
            .confirmationDialog(
                "Delete Invoice",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let id = invoiceToDelete {
                        Task { await viewModel.deleteInvoice(id: id) }
                    }
                }
                Button("Cancel", role: .cancel) {
                    invoiceToDelete = nil
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

                if viewModel.overdueCount > 0 {
                    overdueBanner
                        .padding(.horizontal, SpacingTokens.md)
                }

                filterPicker
                    .padding(.bottom, SpacingTokens.xxs)

                invoiceList
                    .padding(.horizontal, SpacingTokens.md)

                Color.clear.frame(height: SpacingTokens.xl)
            }
            .padding(.top, SpacingTokens.sm)
        }
    }

    // MARK: - Metrics row

    private var metricsRow: some View {
        HStack(spacing: SpacingTokens.sm) {
            MetricCard(label: "Outstanding", value: formatted(viewModel.totalOutstanding))
            MetricCard(label: "Paid", value: formatted(totalPaid))
            MetricCard(label: "Overdue", value: "\(viewModel.overdueCount)")
        }
    }

    private var totalPaid: Decimal {
        viewModel.invoices.reduce(Decimal.zero) { $0 + $1.amountPaid }
    }

    private func formatted(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter.string(from: amount as NSDecimalNumber) ?? "$0"
    }

    // MARK: - Overdue banner

    private var overdueBanner: some View {
        HStack(spacing: SpacingTokens.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.body)
                .foregroundStyle(ColorTokens.error)
                .frame(width: 36, height: 36)
                .background(
                    ColorTokens.error.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: RadiusTokens.small)
                )

            VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                Text("\(viewModel.overdueCount) invoice\(viewModel.overdueCount == 1 ? "" : "s") past due")
                    .font(TypographyTokens.subheadline)
                    .fontWeight(.semibold)
                Text("Tap a row to review and send a reminder.")
                    .font(TypographyTokens.caption)
                    .foregroundStyle(ColorTokens.secondaryText)
            }

            Spacer()
        }
        .padding(SpacingTokens.sm)
        .background(
            ColorTokens.error.opacity(0.08),
            in: RoundedRectangle(cornerRadius: RadiusTokens.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: RadiusTokens.card)
                .strokeBorder(ColorTokens.error.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - Invoice list

    private var invoiceList: some View {
        Group {
            if viewModel.filteredInvoices.isEmpty {
                filteredEmptyView
            } else {
                LazyVStack(spacing: SpacingTokens.sm) {
                    ForEach(viewModel.filteredInvoices) { invoice in
                        NavigationLink(value: AppDestination.invoicePreview(id: invoice.id)) {
                            InvoiceRowView(invoice: invoice)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if invoice.status == .draft {
                                Button(role: .destructive) {
                                    invoiceToDelete = invoice.id
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
    }

    private var filteredEmptyView: some View {
        VStack(spacing: SpacingTokens.sm) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 36))
                .foregroundStyle(ColorTokens.secondaryText)
            Text(viewModel.searchText.isEmpty ? "No invoices in \(viewModel.selectedFilter.title.lowercased())" : "No matches")
                .font(TypographyTokens.subheadline)
                .foregroundStyle(ColorTokens.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SpacingTokens.xxl)
    }

    // MARK: - Empty state (no invoices at all)

    private var emptyState: some View {
        EmptyStateView(
            icon: "dollarsign.circle",
            title: "No Invoices",
            subtitle: "Invoices are created from an approved estimate inside a project. Open a project and long-press an estimate to bill it.",
            ctaTitle: "Go to Projects",
            ctaAction: { appState.selectedTab = .projects }
        )
        .padding(.horizontal, SpacingTokens.md)
    }

    // MARK: - Filter pills

    private var filterPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: SpacingTokens.xs) {
                ForEach(InvoiceStatusFilter.allCases) { filter in
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

    private func count(for filter: InvoiceStatusFilter) -> Int {
        if filter == .all { return viewModel.invoices.count }
        return viewModel.invoices.filter { filter.matchingStatuses.contains($0.status) }.count
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

private struct InvoiceRowView: View {
    let invoice: Invoice

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xs) {
            HStack(spacing: SpacingTokens.sm) {
                // Leading icon block
                Image(systemName: leadingIcon)
                    .font(.title3)
                    .foregroundStyle(leadingIconColor)
                    .frame(width: 44, height: 44)
                    .background(
                        leadingIconColor.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: RadiusTokens.small)
                    )

                VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                    Text(invoice.invoiceNumber)
                        .font(TypographyTokens.headline)
                        .foregroundStyle(ColorTokens.primaryText)

                    HStack(spacing: SpacingTokens.xs) {
                        statusBadge

                        if let dueDate = invoice.dueDate {
                            Text("·")
                                .font(TypographyTokens.caption2)
                                .foregroundStyle(.tertiary)

                            HStack(spacing: 2) {
                                Image(systemName: "clock")
                                    .font(.caption2)
                                Text(dueDate.formatted(as: .relative))
                                    .font(TypographyTokens.caption2)
                            }
                            .foregroundStyle(invoice.isPastDue ? ColorTokens.error : ColorTokens.tertiaryText)
                        }
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: SpacingTokens.xxs) {
                    CurrencyText(
                        amount: invoice.amountDue,
                        font: invoice.status == .overdue
                            ? TypographyTokens.moneyMedium
                            : TypographyTokens.moneySmall
                    )
                    .foregroundStyle(invoice.status == .overdue ? ColorTokens.error : ColorTokens.primaryText)

                    if invoice.amountPaid > 0 && invoice.status != .paid {
                        Text("of \(formatted(invoice.totalAmount))")
                            .font(TypographyTokens.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            // Payment progress bar for partially paid invoices
            if invoice.status == .partiallyPaid || (invoice.amountPaid > 0 && invoice.status != .paid) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(ColorTokens.progressTrack)
                            .frame(height: 4)

                        Capsule()
                            .fill(ColorTokens.success)
                            .frame(width: geo.size.width * invoice.paymentProgress, height: 4)
                    }
                }
                .frame(height: 4)
                .padding(.leading, 44 + SpacingTokens.sm) // align with text column
            }
        }
        .padding(SpacingTokens.md)
        .glassCard()
    }

    private var leadingIcon: String {
        switch invoice.status {
        case .draft: "doc.text"
        case .sent, .viewed: "paperplane"
        case .paid: "checkmark.circle.fill"
        case .partiallyPaid: "hourglass"
        case .overdue: "exclamationmark.triangle.fill"
        case .void: "xmark.circle"
        }
    }

    private var leadingIconColor: Color {
        switch invoice.status {
        case .draft: ColorTokens.secondaryText
        case .sent, .viewed: ColorTokens.accentBlue
        case .partiallyPaid: ColorTokens.warning
        case .paid: ColorTokens.success
        case .overdue: ColorTokens.error
        case .void: ColorTokens.secondaryText
        }
    }

    private var statusBadge: some View {
        let (text, color): (String, Color) = {
            switch invoice.status {
            case .draft: ("Draft", ColorTokens.secondaryText)
            case .sent: ("Sent", ColorTokens.accentBlue)
            case .viewed: ("Viewed", ColorTokens.accentBlue)
            case .partiallyPaid: ("Partial", ColorTokens.warning)
            case .paid: ("Paid", ColorTokens.success)
            case .overdue: ("Overdue", ColorTokens.error)
            case .void: ("Void", ColorTokens.secondaryText)
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

    private func formatted(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter.string(from: amount as NSDecimalNumber) ?? "$0"
    }
}

// MARK: - Preview

#Preview {
    InvoiceListView()
        .environment(AppRouter())
        .environment(AppState())
}
