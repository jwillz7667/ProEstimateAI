import SwiftUI

/// Invoices tab landing page. Lists every invoice for the company with a
/// headline "outstanding balance" summary, status badges, and balance-due
/// amounts. Tapping a row pushes the invoice detail onto the tab's
/// `NavigationStack` (owned by `MainTabView`, which applies
/// `.appNavigationDestinations()` to resolve `AppDestination.invoiceDetail`).
///
/// Invoices are created by converting an approved estimate inside a project
/// (the product loop), so there's no "+" creation button here — the empty
/// state points contractors back to that flow instead of opening a
/// dead-end blank invoice.
struct InvoiceListView: View {
    @State private var viewModel = InvoiceListViewModel()

    var body: some View {
        content
            .navigationTitle("Invoices")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SubscriptionBadge()
                }
            }
            .searchable(text: $viewModel.searchText, prompt: "Search invoices")
            .refreshable {
                await viewModel.refresh()
            }
            .task {
                if !viewModel.hasInvoices {
                    await viewModel.loadInvoices()
                }
            }
            .onAppear {
                // Silently re-sync when returning from the detail screen so a
                // sent / paid / deleted invoice reflects here without a manual
                // pull-to-refresh. Skips the very first appearance (handled by
                // `.task`); the reload keeps `isLoading` true but the content
                // switch only shows the spinner when the list is empty, so
                // there's no flash over already-loaded rows.
                if viewModel.hasInvoices {
                    Task { await viewModel.loadInvoices() }
                }
            }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && !viewModel.hasInvoices {
            LoadingStateView(message: "Loading invoices...")
        } else if let errorMessage = viewModel.errorMessage, !viewModel.hasInvoices {
            RetryStateView(message: errorMessage) {
                Task { await viewModel.loadInvoices() }
            }
        } else if !viewModel.hasInvoices {
            EmptyStateView(
                icon: "doc.plaintext",
                title: "No Invoices Yet",
                subtitle: "Create an invoice from an approved estimate inside a project to start billing clients."
            )
        } else {
            invoiceList
        }
    }

    // MARK: - Invoice List

    private var invoiceList: some View {
        ScrollView {
            LazyVStack(spacing: SpacingTokens.sm) {
                if viewModel.totalOutstanding > 0 {
                    outstandingSummary
                }

                ForEach(viewModel.filteredInvoices) { invoice in
                    NavigationLink(value: AppDestination.invoiceDetail(id: invoice.id)) {
                        invoiceRow(invoice)
                            .padding(SpacingTokens.md)
                            .glassCard()
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens this invoice")
                }
            }
            .padding(.horizontal, SpacingTokens.md)
            .padding(.vertical, SpacingTokens.xs)
        }
    }

    // MARK: - Outstanding Summary

    private var outstandingSummary: some View {
        HStack {
            VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                Text("Outstanding")
                    .font(TypographyTokens.caption)
                    .foregroundStyle(.secondary)
                CurrencyText(amount: viewModel.totalOutstanding, font: TypographyTokens.moneyLarge)
            }
            Spacer()
            Image(systemName: "banknote")
                .font(.title2)
                .foregroundStyle(ColorTokens.primaryOrange)
        }
        .padding(SpacingTokens.md)
        .glassCard()
    }

    // MARK: - Invoice Row

    private func invoiceRow(_ invoice: Invoice) -> some View {
        HStack(spacing: SpacingTokens.sm) {
            Image(systemName: "doc.plaintext.fill")
                .font(.title3)
                .foregroundStyle(ColorTokens.primaryOrange)
                .frame(width: 36, height: 36)
                .background(ColorTokens.primaryOrange.opacity(0.12), in: RoundedRectangle(cornerRadius: RadiusTokens.small))

            VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                Text(invoice.invoiceNumber)
                    .font(TypographyTokens.headline)
                    .foregroundStyle(ColorTokens.primaryText)

                StatusBadge(text: invoice.statusLabel, style: invoice.statusBadgeStyle)

                if let dueDate = invoice.dueDate, !invoice.isPaid {
                    Text("Due \(dueDate.formatted(as: .medium))")
                        .font(TypographyTokens.caption2)
                        .foregroundStyle(invoice.isPastDue ? ColorTokens.error : .secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: SpacingTokens.xxs) {
                CurrencyText(
                    amount: invoice.isPaid ? invoice.totalAmount : invoice.amountDue,
                    font: TypographyTokens.moneyMedium
                )
                Text(invoice.isPaid ? "Paid" : "Balance due")
                    .font(TypographyTokens.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        InvoiceListView()
    }
}
