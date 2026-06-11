import SwiftUI

/// Full invoice detail screen. Renders the payment status, money breakdown,
/// line items, and terms, plus the lifecycle actions a contractor takes on a
/// bill: send a draft, record payment, export the server-rendered PDF, and
/// delete.
///
/// The screen is reachable two ways and must work in both:
///  - **Pushed** onto the Invoices tab's `NavigationStack` (from the list).
///  - **Presented in a sheet** straight after converting an estimate, where
///    a trailing "Done" button dismisses the sheet (`isPresentedInSheet`).
///
/// In both cases `@Environment(\.dismiss)` does the right thing — it pops the
/// pushed view or closes the sheet — so deletion can simply call `dismiss()`.
struct InvoiceDetailView: View {
    let invoiceId: String
    /// When `true` the screen was presented modally (e.g. right after an
    /// estimate→invoice conversion) and shows a "Done" button to close.
    var isPresentedInSheet: Bool = false

    @State private var viewModel = InvoiceDetailViewModel()
    @State private var exportedPDF: ExportedPDF?
    @State private var showDeleteConfirmation = false

    @Environment(\.dismiss) private var dismiss

    /// Identifiable wrapper so the share sheet can be driven by `.sheet(item:)`
    /// — the file URL is the identity, matching `ProjectDetailView`.
    private struct ExportedPDF: Identifiable, Hashable {
        let url: URL
        var id: URL { url }
    }

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.invoice == nil {
                LoadingStateView(message: "Loading invoice...")
            } else if let error = viewModel.errorMessage, viewModel.invoice == nil {
                RetryStateView(message: error) {
                    Task { await viewModel.load(id: invoiceId) }
                }
            } else if let invoice = viewModel.invoice {
                invoiceContent(invoice)
            } else {
                LoadingStateView(message: "Loading invoice...")
                    .onAppear {
                        Task { await viewModel.load(id: invoiceId) }
                    }
            }
        }
        .navigationTitle(viewModel.invoice?.invoiceNumber ?? "Invoice")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isPresentedInSheet {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .refreshable {
            await viewModel.load(id: invoiceId)
        }
        .task {
            if viewModel.invoice == nil {
                await viewModel.load(id: invoiceId)
            }
        }
        .sheet(item: $exportedPDF) { pdf in
            ActivityViewRepresentable(activityItems: [pdf.url])
        }
        .confirmationDialog(
            "Delete Invoice",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Permanently", role: .destructive) {
                Task {
                    if await viewModel.delete() {
                        dismiss()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes the invoice and its line items. This cannot be undone.")
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { viewModel.actionError != nil },
                set: { if !$0 { viewModel.actionError = nil } }
            )
        ) {
            Button("OK") { viewModel.actionError = nil }
        } message: {
            if let message = viewModel.actionError {
                Text(message)
            }
        }
    }

    // MARK: - Content

    private func invoiceContent(_ invoice: Invoice) -> some View {
        ScrollView {
            LazyVStack(spacing: SpacingTokens.lg) {
                statusHeader(invoice)
                amountCard(invoice)
                totalsBreakdown(invoice)

                if !viewModel.lineItems.isEmpty {
                    lineItemsSection
                }

                if hasTerms(invoice) {
                    termsCard(invoice)
                }

                actions(invoice)

                Spacer(minLength: SpacingTokens.huge)
            }
            .padding(.horizontal, SpacingTokens.md)
            .padding(.vertical, SpacingTokens.sm)
        }
    }

    // MARK: - Status Header

    private func statusHeader(_ invoice: Invoice) -> some View {
        VStack(alignment: .leading, spacing: SpacingTokens.sm) {
            HStack {
                VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                    Text(invoice.invoiceNumber)
                        .font(TypographyTokens.title3)
                        .foregroundStyle(ColorTokens.primaryText)
                    StatusBadge(text: invoice.statusLabel, style: invoice.statusBadgeStyle)
                }
                Spacer()
                Image(systemName: "doc.plaintext.fill")
                    .font(.title)
                    .foregroundStyle(ColorTokens.primaryOrange)
            }

            if invoice.issuedDate != nil || invoice.dueDate != nil {
                Divider()
                HStack(spacing: SpacingTokens.lg) {
                    if let issuedDate = invoice.issuedDate {
                        dateColumn(title: "Issued", value: issuedDate.formatted(as: .invoiceDate), isAlert: false)
                    }
                    if let dueDate = invoice.dueDate {
                        dateColumn(
                            title: "Due",
                            value: dueDate.formatted(as: .invoiceDate),
                            isAlert: invoice.isPastDue
                        )
                    }
                    Spacer()
                }
            }

            if invoice.isPastDue {
                Label("Past due", systemImage: "exclamationmark.triangle.fill")
                    .font(TypographyTokens.caption)
                    .foregroundStyle(ColorTokens.error)
            }
        }
        .padding(SpacingTokens.md)
        .glassCard()
    }

    private func dateColumn(title: String, value: String, isAlert: Bool) -> some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
            Text(title)
                .font(TypographyTokens.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(TypographyTokens.subheadline)
                .foregroundStyle(isAlert ? ColorTokens.error : ColorTokens.primaryText)
        }
    }

    // MARK: - Amount Card

    /// Headline money figure — the balance the contractor is chasing, or the
    /// settled total once paid.
    private func amountCard(_ invoice: Invoice) -> some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xs) {
            Text(invoice.isPaid ? "Total Paid" : "Balance Due")
                .font(TypographyTokens.caption)
                .foregroundStyle(.secondary)
            CurrencyText(
                amount: invoice.isPaid ? invoice.totalAmount : invoice.amountDue,
                font: TypographyTokens.moneyLarge
            )
            .foregroundStyle(invoice.isPastDue ? ColorTokens.error : ColorTokens.primaryText)

            if invoice.isPartiallyPaid, !invoice.isPaid {
                Text("\(currency(invoice.amountPaid)) paid of \(currency(invoice.totalAmount))")
                    .font(TypographyTokens.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SpacingTokens.md)
        .glassCard()
    }

    // MARK: - Totals Breakdown

    private func totalsBreakdown(_ invoice: Invoice) -> some View {
        VStack(spacing: SpacingTokens.xs) {
            totalRow(label: "Subtotal", amount: invoice.subtotal)

            if invoice.discountAmount > 0 {
                totalRow(label: "Discount", amount: -invoice.discountAmount)
            }

            totalRow(label: "Tax", amount: invoice.taxAmount)

            Divider()

            totalRow(label: "Total", amount: invoice.totalAmount, emphasized: true)

            if invoice.amountPaid > 0 {
                totalRow(label: "Amount Paid", amount: -invoice.amountPaid)
                Divider()
                totalRow(label: "Balance Due", amount: invoice.amountDue, emphasized: true)
            }
        }
        .padding(SpacingTokens.md)
        .glassCard()
    }

    private func totalRow(label: String, amount: Decimal, emphasized: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(emphasized ? TypographyTokens.headline : TypographyTokens.subheadline)
                .foregroundStyle(emphasized ? ColorTokens.primaryText : ColorTokens.secondaryText)
            Spacer()
            CurrencyText(
                amount: amount,
                font: emphasized ? TypographyTokens.moneyMedium : TypographyTokens.moneySmall
            )
        }
    }

    // MARK: - Line Items

    private var lineItemsSection: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xs) {
            Text("Line Items")
                .font(TypographyTokens.headline)
                .foregroundStyle(ColorTokens.primaryText)

            VStack(spacing: SpacingTokens.sm) {
                ForEach(viewModel.lineItems) { item in
                    lineItemRow(item)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func lineItemRow(_ item: InvoiceLineItem) -> some View {
        HStack(alignment: .top, spacing: SpacingTokens.sm) {
            VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                Text(item.name)
                    .font(TypographyTokens.subheadline.weight(.semibold))
                    .foregroundStyle(ColorTokens.primaryText)

                if let description = item.description, !description.isEmpty {
                    Text(description)
                        .font(TypographyTokens.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: SpacingTokens.xxs) {
                    Text("\(formattedQuantity(item.quantity)) \(item.unit) ×")
                    CurrencyText(amount: item.unitCost, font: TypographyTokens.caption)
                }
                .font(TypographyTokens.caption)
                .foregroundStyle(.tertiary)
            }

            Spacer(minLength: SpacingTokens.sm)

            CurrencyText(amount: item.lineTotal, font: TypographyTokens.moneySmall)
        }
        .padding(SpacingTokens.md)
        .glassCard()
    }

    // MARK: - Terms

    private func termsCard(_ invoice: Invoice) -> some View {
        VStack(alignment: .leading, spacing: SpacingTokens.sm) {
            if let instructions = invoice.paymentInstructions, !instructions.isEmpty {
                VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                    Text("Payment Instructions")
                        .font(TypographyTokens.caption2)
                        .foregroundStyle(.secondary)
                    Text(instructions)
                        .font(TypographyTokens.subheadline)
                        .foregroundStyle(ColorTokens.primaryText)
                }
            }

            if let notes = invoice.notes, !notes.isEmpty {
                if invoice.paymentInstructions?.isEmpty == false {
                    Divider()
                }
                VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                    Text("Notes")
                        .font(TypographyTokens.caption2)
                        .foregroundStyle(.secondary)
                    Text(notes)
                        .font(TypographyTokens.subheadline)
                        .foregroundStyle(ColorTokens.primaryText)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SpacingTokens.md)
        .glassCard()
    }

    // MARK: - Actions

    private func actions(_ invoice: Invoice) -> some View {
        VStack(spacing: SpacingTokens.sm) {
            if invoice.status == .draft {
                PrimaryCTAButton(
                    title: "Send Invoice",
                    icon: "paperplane.fill",
                    isLoading: viewModel.isPerformingAction,
                    isDisabled: viewModel.isPerformingAction || viewModel.isExporting
                ) {
                    Task { await viewModel.markAsSent() }
                }
            }

            if canMarkPaid(invoice) {
                SecondaryButton(
                    title: "Mark as Paid",
                    icon: "checkmark.circle.fill",
                    isLoading: viewModel.isPerformingAction,
                    emphasis: .accent
                ) {
                    Task { await viewModel.markAsPaid() }
                }
            }

            SecondaryButton(
                title: "Export PDF",
                icon: "square.and.arrow.up",
                isLoading: viewModel.isExporting
            ) {
                Task {
                    if let url = await viewModel.exportPDF() {
                        exportedPDF = ExportedPDF(url: url)
                    }
                }
            }

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete Invoice", systemImage: "trash")
                    .font(TypographyTokens.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SpacingTokens.sm)
            }
            .foregroundStyle(ColorTokens.error)
            .disabled(viewModel.isPerformingAction || viewModel.isExporting)
            .padding(.top, SpacingTokens.xs)
        }
    }

    // MARK: - Helpers

    /// Payment can be recorded for any non-paid, non-void invoice that still
    /// carries a balance. Draft invoices are included so a contractor who got
    /// paid in cash before sending can close the loop in one tap.
    private func canMarkPaid(_ invoice: Invoice) -> Bool {
        invoice.status != .paid && invoice.status != .void && invoice.amountDue > 0
    }

    private func hasTerms(_ invoice: Invoice) -> Bool {
        let hasNotes = !(invoice.notes ?? "").isEmpty
        let hasInstructions = !(invoice.paymentInstructions ?? "").isEmpty
        return hasNotes || hasInstructions
    }

    private func formattedQuantity(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "\(value)"
    }

    private func currency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "\(value)"
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        InvoiceDetailView(invoiceId: "inv-001")
    }
}
