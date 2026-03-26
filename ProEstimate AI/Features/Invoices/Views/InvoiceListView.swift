import SwiftUI

struct InvoiceListView: View {
    @State private var viewModel = InvoiceListViewModel()
    @State private var showingDeleteConfirmation = false
    @State private var invoiceToDelete: String?

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.invoices.isEmpty {
                    LoadingStateView(message: "Loading invoices...")
                } else if viewModel.filteredInvoices.isEmpty {
                    emptyState
                } else {
                    invoiceList
                }
            }
            .navigationTitle("Invoices")
            .searchable(text: $viewModel.searchText, prompt: "Search invoices...")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        // Create new invoice action
                    } label: {
                        Image(systemName: "plus")
                            .fontWeight(.semibold)
                            .foregroundStyle(ColorTokens.primaryOrange)
                    }
                }
            }
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

    // MARK: - Subviews

    private var emptyState: some View {
        VStack(spacing: 0) {
            filterPicker
            Spacer()
            EmptyStateView(
                icon: "dollarsign.circle",
                title: "No Invoices",
                subtitle: viewModel.searchText.isEmpty
                    ? "Create your first invoice from an approved estimate."
                    : "No invoices match your search.",
                ctaTitle: viewModel.searchText.isEmpty ? "Create Invoice" : nil,
                ctaAction: viewModel.searchText.isEmpty ? {} : nil
            )
            Spacer()
        }
    }

    private var invoiceList: some View {
        VStack(spacing: 0) {
            // Outstanding summary
            if viewModel.totalOutstanding > 0 {
                outstandingSummary
            }

            filterPicker

            List {
                ForEach(viewModel.filteredInvoices) { invoice in
                    NavigationLink(value: AppDestination.invoicePreview(id: invoice.id)) {
                        InvoiceRowView(invoice: invoice)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
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
            .listStyle(.plain)
        }
    }

    private var outstandingSummary: some View {
        HStack(spacing: SpacingTokens.md) {
            VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                Text("Outstanding")
                    .font(TypographyTokens.caption)
                    .foregroundStyle(.secondary)
                CurrencyText(amount: viewModel.totalOutstanding, font: TypographyTokens.moneyMedium)
            }

            Spacer()

            if viewModel.overdueCount > 0 {
                VStack(alignment: .trailing, spacing: SpacingTokens.xxs) {
                    Text("Overdue")
                        .font(TypographyTokens.caption)
                        .foregroundStyle(ColorTokens.error)
                    Text("\(viewModel.overdueCount)")
                        .font(TypographyTokens.moneyMedium)
                        .foregroundStyle(ColorTokens.error)
                }
            }
        }
        .padding(SpacingTokens.md)
        .glassCard()
        .padding(.horizontal, SpacingTokens.md)
        .padding(.top, SpacingTokens.xs)
    }

    private var filterPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: SpacingTokens.xs) {
                ForEach(InvoiceStatusFilter.allCases) { filter in
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

private struct InvoiceRowView: View {
    let invoice: Invoice

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xs) {
            HStack {
                Text(invoice.invoiceNumber)
                    .font(TypographyTokens.headline)

                Spacer()

                StatusBadge(
                    text: statusDisplayText,
                    style: statusBadgeStyle
                )
            }

            HStack {
                CurrencyText(
                    amount: invoice.amountDue,
                    font: invoice.status == .overdue
                        ? TypographyTokens.moneyMedium
                        : TypographyTokens.moneySmall
                )
                .foregroundStyle(invoice.status == .overdue ? ColorTokens.error : .primary)

                if invoice.amountPaid > 0 && invoice.status != .paid {
                    Text("of")
                        .font(TypographyTokens.caption)
                        .foregroundStyle(.tertiary)
                    CurrencyText(amount: invoice.totalAmount, font: TypographyTokens.moneyCaption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let dueDate = invoice.dueDate {
                    Label(dueDate.formatted(as: .relative), systemImage: "clock")
                        .font(TypographyTokens.caption)
                        .foregroundStyle(invoice.isPastDue ? ColorTokens.error : Color.gray.opacity(0.6))
                }
            }

            // Payment progress bar for partially paid
            if invoice.status == .partiallyPaid || (invoice.amountPaid > 0 && invoice.status != .paid) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.gray.opacity(0.15))
                            .frame(height: 4)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(ColorTokens.success)
                            .frame(width: geo.size.width * invoice.paymentProgress, height: 4)
                    }
                }
                .frame(height: 4)
            }
        }
        .padding(.vertical, SpacingTokens.xxs)
    }

    private var statusDisplayText: String {
        switch invoice.status {
        case .partiallyPaid: "Partial"
        default: invoice.status.rawValue.capitalized
        }
    }

    private var statusBadgeStyle: StatusBadge.Style {
        switch invoice.status {
        case .draft: .neutral
        case .sent, .viewed: .info
        case .partiallyPaid: .warning
        case .paid: .success
        case .overdue: .error
        case .void: .neutral
        }
    }
}

// MARK: - Preview

#Preview {
    InvoiceListView()
}
