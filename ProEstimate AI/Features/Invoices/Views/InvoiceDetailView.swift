import SwiftUI

/// Invoice detail + payment screen, presented as a sheet from the project
/// detail screen. Shows the invoice's line items and totals, and exposes the
/// two get-paid actions: send the invoice to the client and mark it paid.
struct InvoiceDetailView: View {
    /// Optional client name for the "Billed to" line. The host supplies it
    /// from the already-loaded project client so the sheet doesn't re-fetch.
    var clientName: String?

    @State private var viewModel: InvoiceDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    init(invoice: Invoice, clientName: String? = nil) {
        self.clientName = clientName
        _viewModel = State(initialValue: InvoiceDetailViewModel(invoice: invoice))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: SpacingTokens.lg) {
                    headerCard
                    if !viewModel.lineItems.isEmpty {
                        lineItemsCard
                    }
                    totalsCard
                    if hasFooterText {
                        footerCard
                    }
                    actions
                    Spacer(minLength: SpacingTokens.lg)
                }
                .padding(SpacingTokens.md)
            }
            .background(ColorTokens.background.ignoresSafeArea())
            .navigationTitle(viewModel.invoice.invoiceNumber)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .overlay {
                if viewModel.isSending || viewModel.isMarkingPaid {
                    Color.black.opacity(0.2).ignoresSafeArea()
                        .overlay {
                            ProgressView(viewModel.isMarkingPaid ? "Recording payment…" : "Sending invoice…")
                                .padding()
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }
                }
            }
            .alert(
                "Error",
                isPresented: Binding(
                    get: { viewModel.errorMessage != nil },
                    set: { if !$0 { viewModel.errorMessage = nil } }
                )
            ) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                if let message = viewModel.errorMessage { Text(message) }
            }
            .task { await viewModel.load() }
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: SpacingTokens.sm) {
                HStack {
                    VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                        Text(viewModel.invoice.invoiceNumber)
                            .font(TypographyTokens.title3)
                        if let clientName, !clientName.isEmpty {
                            Text("Billed to \(clientName)")
                                .font(TypographyTokens.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    StatusBadge(text: statusName, style: statusStyle)
                }

                Divider()

                VStack(spacing: SpacingTokens.xxs) {
                    if let issued = viewModel.invoice.issuedDate {
                        dateRow(label: "Issued", value: issued.formatted(as: .invoiceDate))
                    }
                    if let due = viewModel.invoice.dueDate {
                        dateRow(label: "Due", value: due.formatted(as: .invoiceDate))
                    }
                    if let paid = viewModel.invoice.paidAt {
                        dateRow(label: "Paid", value: paid.formatted(as: .invoiceDate))
                    }
                }
            }
        }
    }

    private func dateRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(TypographyTokens.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(TypographyTokens.caption.weight(.medium))
                .foregroundStyle(ColorTokens.primaryText)
        }
    }

    // MARK: - Line Items

    private var lineItemsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: SpacingTokens.sm) {
                Text("Line Items")
                    .font(TypographyTokens.headline)

                ForEach(viewModel.lineItems) { item in
                    VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(TypographyTokens.subheadline.weight(.medium))
                                    .foregroundStyle(ColorTokens.primaryText)
                                if let description = item.description, !description.isEmpty {
                                    Text(description)
                                        .font(TypographyTokens.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            Spacer()
                            CurrencyText(amount: item.lineTotal, font: TypographyTokens.moneySmall)
                        }
                        if item.id != viewModel.lineItems.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Totals

    private var totalsCard: some View {
        GlassCard {
            VStack(spacing: SpacingTokens.xs) {
                totalRow(label: "Subtotal", amount: viewModel.invoice.subtotal)
                if viewModel.invoice.discountAmount > 0 {
                    totalRow(label: "Discount", amount: -viewModel.invoice.discountAmount)
                }
                if viewModel.invoice.taxAmount > 0 {
                    totalRow(label: "Tax", amount: viewModel.invoice.taxAmount)
                }
                Divider()
                totalRow(label: "Total", amount: viewModel.invoice.totalAmount, emphasized: true)
                if viewModel.invoice.amountPaid > 0 {
                    totalRow(label: "Paid", amount: viewModel.invoice.amountPaid)
                    Divider()
                    totalRow(label: "Balance Due", amount: viewModel.invoice.amountDue, emphasized: true)
                }
            }
        }
    }

    private func totalRow(label: String, amount: Decimal, emphasized: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(emphasized ? TypographyTokens.headline : TypographyTokens.subheadline)
                .foregroundStyle(emphasized ? ColorTokens.primaryText : Color.secondary)
            Spacer()
            CurrencyText(
                amount: amount,
                font: emphasized ? TypographyTokens.moneyMedium : TypographyTokens.moneySmall
            )
        }
    }

    // MARK: - Footer (notes + payment instructions)

    private var hasFooterText: Bool {
        let notes = viewModel.invoice.notes?.isEmpty == false
        let instructions = viewModel.invoice.paymentInstructions?.isEmpty == false
        return notes || instructions
    }

    private var footerCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: SpacingTokens.sm) {
                if let instructions = viewModel.invoice.paymentInstructions, !instructions.isEmpty {
                    VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                        Text("Payment Instructions")
                            .font(TypographyTokens.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(instructions)
                            .font(TypographyTokens.subheadline)
                            .foregroundStyle(ColorTokens.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let notes = viewModel.invoice.notes, !notes.isEmpty {
                    VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                        Text("Notes")
                            .font(TypographyTokens.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(notes)
                            .font(TypographyTokens.subheadline)
                            .foregroundStyle(ColorTokens.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: SpacingTokens.sm) {
            if viewModel.invoice.canSend {
                PrimaryCTAButton(
                    title: "Send Invoice to Client",
                    icon: "paperplane.fill",
                    isLoading: viewModel.isSending,
                    isDisabled: viewModel.isMarkingPaid
                ) {
                    Task { await viewModel.send() }
                }
            }

            if viewModel.invoice.canMarkPaid {
                SecondaryButton(
                    title: "Mark as Paid",
                    icon: "checkmark.circle.fill",
                    isLoading: viewModel.isMarkingPaid,
                    emphasis: .accent
                ) {
                    Task { await viewModel.markPaid() }
                }
            }

            if viewModel.invoice.isPaid {
                HStack(spacing: SpacingTokens.xs) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(ColorTokens.success)
                    Text("Paid in full")
                        .font(TypographyTokens.subheadline.weight(.semibold))
                        .foregroundStyle(ColorTokens.success)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, SpacingTokens.sm)
            }
        }
    }

    // MARK: - Status Presentation

    private var statusName: String {
        switch viewModel.invoice.status {
        case .draft: "Draft"
        case .sent: "Sent"
        case .viewed: "Viewed"
        case .partiallyPaid: "Partially Paid"
        case .paid: "Paid"
        case .overdue: "Overdue"
        case .void: "Void"
        }
    }

    private var statusStyle: StatusBadge.Style {
        switch viewModel.invoice.status {
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
    InvoiceDetailView(invoice: .sample, clientName: "Jordan Avery")
}
