import SwiftUI

struct InvoicePreviewView: View {
    let invoiceId: String
    @State private var viewModel = InvoiceViewModel()
    @State private var showingMarkPaidConfirmation = false

    var body: some View {
        Group {
            if viewModel.isLoading {
                LoadingStateView(message: "Loading invoice...")
            } else if viewModel.invoice != nil {
                invoiceContent
            } else if let error = viewModel.errorMessage {
                errorState(message: error)
            } else {
                EmptyStateView(
                    icon: "dollarsign.circle",
                    title: "Invoice Not Found",
                    subtitle: "This invoice could not be loaded."
                )
            }
        }
        .navigationTitle("Invoice")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: SpacingTokens.sm) {
                    if let invoice = viewModel.invoice {
                        StatusBadge(
                            text: invoice.status.rawValue.capitalized,
                            style: viewModel.statusBadgeStyle
                        )
                    }

                    Menu {
                        ShareLink(item: "Invoice \(viewModel.invoice?.invoiceNumber ?? "")") {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }

                        Button {
                            // PDF export placeholder
                        } label: {
                            Label("Export PDF", systemImage: "arrow.down.doc")
                        }

                        if viewModel.canSend {
                            Button {
                                Task { await viewModel.sendInvoice() }
                            } label: {
                                Label("Send to Client", systemImage: "paperplane")
                            }
                        }

                        if viewModel.canMarkPaid {
                            Button {
                                showingMarkPaidConfirmation = true
                            } label: {
                                Label("Mark as Paid", systemImage: "checkmark.circle")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .task {
            await viewModel.loadInvoice(id: invoiceId)
        }
        .confirmationDialog(
            "Mark as Paid",
            isPresented: $showingMarkPaidConfirmation,
            titleVisibility: .visible
        ) {
            Button("Mark as Paid") {
                Task { await viewModel.markAsPaid() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will record the full remaining balance as paid.")
        }
    }

    // MARK: - Invoice Content

    private var invoiceContent: some View {
        ScrollView {
            VStack(spacing: SpacingTokens.lg) {
                // Company header
                companyHeader

                Divider()
                    .padding(.horizontal, SpacingTokens.lg)

                // Invoice info + client block
                invoiceInfoBlock

                Divider()
                    .padding(.horizontal, SpacingTokens.lg)

                // Line items table
                lineItemsTable

                // Totals section
                InvoiceTotalsSection(
                    subtotal: viewModel.invoice?.subtotal ?? 0,
                    taxAmount: viewModel.invoice?.taxAmount ?? 0,
                    totalAmount: viewModel.invoice?.totalAmount ?? 0,
                    amountPaid: viewModel.invoice?.amountPaid ?? 0,
                    amountDue: viewModel.invoice?.amountDue ?? 0,
                    isPaid: viewModel.invoice?.isFullyPaid ?? false
                )
                .padding(.horizontal, SpacingTokens.md)

                // Notes
                if let notes = viewModel.invoice?.notes, !notes.isEmpty {
                    notesSection(notes)
                }

                // Action buttons
                actionButtons

                Spacer(minLength: SpacingTokens.xxl)
            }
        }
    }

    // MARK: - Subviews

    private var companyHeader: some View {
        VStack(spacing: SpacingTokens.xs) {
            if let logoURL = viewModel.company?.logoURL {
                AsyncImage(url: logoURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 40)
                } placeholder: {
                    companyLogoPlaceholder
                }
            } else {
                companyLogoPlaceholder
            }

            Text(viewModel.company?.name ?? "Company")
                .font(TypographyTokens.title3)

            if let address = viewModel.companyAddress {
                Text(address)
                    .font(TypographyTokens.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: SpacingTokens.md) {
                if let phone = viewModel.company?.phone {
                    Text(phone)
                        .font(TypographyTokens.caption)
                        .foregroundStyle(.secondary)
                }
                if let email = viewModel.company?.email {
                    Text(email)
                        .font(TypographyTokens.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, SpacingTokens.lg)
        .frame(maxWidth: .infinity)
    }

    private var companyLogoPlaceholder: some View {
        Image(systemName: "building.2")
            .font(.system(size: 28))
            .foregroundStyle(ColorTokens.primaryOrange.opacity(0.5))
            .frame(width: 40, height: 40)
    }

    private var invoiceInfoBlock: some View {
        HStack(alignment: .top) {
            // Left: Invoice details
            VStack(alignment: .leading, spacing: SpacingTokens.xs) {
                Text("INVOICE")
                    .font(TypographyTokens.caption)
                    .fontWeight(.bold)
                    .tracking(3)
                    .foregroundStyle(.secondary)

                Text(viewModel.invoice?.invoiceNumber ?? "")
                    .font(TypographyTokens.title2)

                infoRow(label: "Date", value: viewModel.formattedInvoiceDate)

                if let dueDate = viewModel.formattedDueDate {
                    infoRow(
                        label: "Due Date",
                        value: dueDate,
                        isHighlighted: viewModel.invoice?.isPastDue ?? false
                    )
                }

                if let sentDate = viewModel.formattedSentDate {
                    infoRow(label: "Sent", value: sentDate)
                }

                if let paidDate = viewModel.formattedPaidDate {
                    infoRow(label: "Paid", value: paidDate)
                }
            }

            Spacer()

            // Right: Client info
            VStack(alignment: .trailing, spacing: SpacingTokens.xs) {
                Text("BILL TO")
                    .font(TypographyTokens.caption)
                    .fontWeight(.bold)
                    .tracking(3)
                    .foregroundStyle(.secondary)

                Text(viewModel.client?.name ?? "Client")
                    .font(TypographyTokens.headline)

                if let address = viewModel.clientAddress {
                    Text(address)
                        .font(TypographyTokens.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }

                if let email = viewModel.client?.email {
                    Text(email)
                        .font(TypographyTokens.caption)
                        .foregroundStyle(.secondary)
                }

                if let phone = viewModel.client?.phone {
                    Text(phone)
                        .font(TypographyTokens.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, SpacingTokens.lg)
    }

    private var lineItemsTable: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xs) {
            // Table header
            HStack {
                Text("Item")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Qty")
                    .frame(width: 40, alignment: .trailing)
                Text("Unit")
                    .frame(width: 45, alignment: .center)
                Text("Price")
                    .frame(width: 65, alignment: .trailing)
                Text("Total")
                    .frame(width: 75, alignment: .trailing)
            }
            .font(TypographyTokens.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .padding(.horizontal, SpacingTokens.lg)

            Divider()
                .padding(.horizontal, SpacingTokens.lg)

            // Line items
            ForEach(viewModel.lineItems) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.name)
                            .font(TypographyTokens.caption)
                            .lineLimit(2)
                        if let description = item.description {
                            Text(description)
                                .font(TypographyTokens.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text(formattedQuantity(item.quantity))
                        .font(TypographyTokens.caption)
                        .frame(width: 40, alignment: .trailing)

                    Text(item.unit)
                        .font(TypographyTokens.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 45, alignment: .center)

                    CurrencyText(amount: item.unitCost, font: TypographyTokens.moneyCaption)
                        .frame(width: 65, alignment: .trailing)

                    CurrencyText(amount: item.lineTotal, font: TypographyTokens.moneyCaption)
                        .frame(width: 75, alignment: .trailing)
                }
                .padding(.horizontal, SpacingTokens.lg)
                .padding(.vertical, 2)
            }

            Divider()
                .padding(.horizontal, SpacingTokens.lg)
        }
    }

    private func notesSection(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xs) {
            Text("Notes")
                .font(TypographyTokens.subheadline)
                .fontWeight(.semibold)

            Text(notes)
                .font(TypographyTokens.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, SpacingTokens.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionButtons: some View {
        VStack(spacing: SpacingTokens.sm) {
            if viewModel.canSend {
                PrimaryCTAButton(
                    title: "Send Invoice",
                    icon: "paperplane",
                    isLoading: viewModel.isSending
                ) {
                    Task { await viewModel.sendInvoice() }
                }
            }

            if viewModel.canMarkPaid {
                SecondaryButton(
                    title: "Mark as Paid",
                    icon: "checkmark.circle",
                    isLoading: viewModel.isMarkingPaid
                ) {
                    showingMarkPaidConfirmation = true
                }
            }
        }
        .padding(.horizontal, SpacingTokens.lg)
    }

    // MARK: - Helpers

    private func infoRow(label: String, value: String, isHighlighted: Bool = false) -> some View {
        HStack(spacing: SpacingTokens.xs) {
            Text(label)
                .font(TypographyTokens.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(TypographyTokens.caption)
                .fontWeight(.medium)
                .foregroundStyle(isHighlighted ? ColorTokens.error : .primary)
        }
    }

    private func formattedQuantity(_ value: Decimal) -> String {
        let number = NSDecimalNumber(decimal: value)
        if value == Decimal(number.intValue) {
            return "\(number.intValue)"
        }
        return String(format: "%.1f", number.doubleValue)
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: SpacingTokens.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(ColorTokens.warning)

            Text("Failed to Load")
                .font(TypographyTokens.title3)

            Text(message)
                .font(TypographyTokens.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            PrimaryCTAButton(title: "Try Again") {
                Task { await viewModel.loadInvoice(id: invoiceId) }
            }
            .frame(maxWidth: 200)
        }
        .padding(SpacingTokens.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        InvoicePreviewView(invoiceId: "inv-001")
    }
}
