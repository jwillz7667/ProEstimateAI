import SwiftUI

struct InvoiceFinanceView: View {
    enum InitialMode { case overview, schedule }
    let initialMode: InitialMode
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @State private var model: InvoiceFinanceViewModel
    @State private var route: FinanceSheet?
    @State private var didOpenInitialMode = false
    @State private var confirmCancelCheckout = false
    @State private var confirmRefundReview = false

    init(invoiceId: String, initialMode: InitialMode = .overview) {
        self.initialMode = initialMode
        _model = State(initialValue: InvoiceFinanceViewModel(invoiceId: invoiceId,
            service: InvoiceFinanceService(), journal: InvoicePaymentJournal()))
    }

    var body: some View {
        NavigationStack {
            financeForm
            .navigationTitle("Payments & receipts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.disabled(model.isWorking)
                }
            }
            .task(id: "\(appState.currentUser?.id ?? ""):\(appState.currentCompany?.id ?? "")") { await reload() }
            .refreshable { await reload() }
            .sheet(item: $route) { route in
                switch route {
                case .payment: InvoiceReceivedPaymentFormView(model: model)
                case let .schedule(snapshot): InvoicePaymentScheduleView(model: model, snapshot: snapshot)
                }
            }
            .interactiveDismissDisabled(model.isWorking)
            .confirmationDialog("Cancel the pending client checkout?", isPresented: $confirmCancelCheckout, titleVisibility: .visible) {
                Button("Cancel pending checkout", role: .destructive) {
                    Task { _ = await model.cancelCheckout(canManage: appState.currentUser?.isAdmin == true) }
                }
                Button("Keep checkout", role: .cancel) {}
            } message: {
                Text("The client won't be able to pay through that checkout. A payment already processing must finish before another payment can be recorded.")
            }
            .confirmationDialog("Confirm you reviewed the refund balance?", isPresented: $confirmRefundReview, titleVisibility: .visible) {
                Button("Confirm refund review") {
                    Task { _ = await model.reviewRefund(canManage: appState.currentUser?.isAdmin == true) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Review the refund receipt and outstanding balance before allowing future online payments. This action doesn't refund or charge any money.")
            }
            .onChange(of: model.savedRevision) { _, _ in
                AppEventBus.shared.notePaymentChange()
                AppEventBus.shared.noteProjectChange()
            }
        }
    }

    private var financeForm: some View {
        Form {
            if let snapshot = model.snapshot {
                summary(snapshot.invoice)
                pendingSection
                checkoutSection(snapshot)
                if !snapshot.installments.isEmpty {
                    Section("Payment schedule") {
                        ForEach(snapshot.installments) { installment in
                            VStack(alignment: .leading, spacing: SpacingTokens.xs) {
                                HStack { Text(installment.title).font(TypographyTokens.headline); Spacer(); CurrencyText(amount: installment.amount) }
                                if let dueDate = installment.dueDate {
                                    Text("Due \(dueDate.formatted(date: .abbreviated, time: .omitted))")
                                        .font(TypographyTokens.caption).foregroundStyle(ColorTokens.secondaryText)
                                }
                                HStack { Text("Outstanding").font(TypographyTokens.caption); Spacer(); CurrencyText(amount: installment.amountDue) }
                            }
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                Section("Receipts and adjustments") {
                    if snapshot.payments.isEmpty {
                        Text("No payment receipts recorded yet.").foregroundStyle(ColorTokens.secondaryText)
                    }
                    ForEach(snapshot.payments) { receipt in
                        InvoicePaymentReceiptRow(receipt: receipt)
                    }
                }
                Section {
                    if snapshot.invoice.status == .draft {
                        Button("Set deposit & payment schedule") { route = .schedule(snapshot) }
                            .disabled(!model.canEditSchedule || appState.currentUser?.canEdit != true)
                        Text("Set the requested payments before sending the invoice.")
                            .font(TypographyTokens.footnote).foregroundStyle(ColorTokens.secondaryText)
                    } else if snapshot.invoice.status != .void {
                        Button("Record received payment") { route = .payment }
                            .disabled(!model.canRecordNewPayment || appState.currentUser?.canEdit != true)
                    }
                    if let url = snapshot.shareURL {
                        ShareLink(item: url) { Label("Share client invoice", systemImage: "square.and.arrow.up") }
                    }
                }
            } else if model.isLoading {
                ProgressView("Loading payment history…")
            }
            if let message = model.errorMessage {
                Section {
                    Text(message).fixedSize(horizontal: false, vertical: true)
                    Button("Refresh payment history") { Task { await reload() } }
                        .disabled(model.isLoading || model.isWorking)
                }
            }
        }
    }

    @ViewBuilder private func checkoutSection(_ snapshot: InvoiceFinanceSnapshot) -> some View {
        if let checkout = snapshot.checkout {
            if let attempt = checkout.activeAttempt {
                Section("Client checkout in progress") {
                    LabeledContent("Payment") { CurrencyText(amount: attempt.amount) }
                    Text(attempt.state.uppercased() == "PROCESSING"
                         ? "The client's payment is processing. Refresh to confirm its result before recording another payment."
                         : "A client checkout is open. Close it before recording payment received another way.")
                        .font(TypographyTokens.footnote).fixedSize(horizontal: false, vertical: true)
                    if appState.currentUser?.isAdmin == true {
                        Button("Cancel pending checkout", role: .destructive) { confirmCancelCheckout = true }
                            .disabled(model.isWorking || model.isLoading || attempt.state.uppercased() == "PROCESSING")
                    }
                }
            }
            if checkout.requiresRefundReview {
                Section("Refund review required") {
                    Text("A refund changed this invoice's balance. An owner or administrator must review the receipts before online payments resume.")
                        .font(TypographyTokens.footnote).fixedSize(horizontal: false, vertical: true)
                    if appState.currentUser?.isAdmin == true {
                        Button("Review refund adjustment") { confirmRefundReview = true }
                            .disabled(model.isWorking || model.isLoading)
                    }
                }
            }
        }
    }

    private func summary(_ invoice: Invoice) -> some View {
        Section(invoice.invoiceNumber) {
            LabeledContent("Invoice total") { CurrencyText(amount: invoice.totalAmount) }
            LabeledContent("Recorded paid") { CurrencyText(amount: invoice.amountPaid) }
            LabeledContent("Outstanding") { CurrencyText(amount: invoice.amountDue) }.fontWeight(.semibold)
        }
    }

    @ViewBuilder private var pendingSection: some View {
        if let pending = model.pendingPayment {
            Section("Pending confirmation") {
                Text("A payment record wasn't confirmed. Review its locked details and check the receipt history before entering another payment.")
                    .fixedSize(horizontal: false, vertical: true)
                LabeledContent("Payment") { CurrencyText(amount: pending.request.amount) }
                LabeledContent("Method", value: pending.request.method.title)
                Button("Review pending payment") { route = .payment }.disabled(model.isWorking)
                Button("Check receipt history") { Task { await reload() } }.disabled(model.isLoading || model.isWorking)
            }
        }
    }

    private func reload() async {
        guard let userId = appState.currentUser?.id, let companyId = appState.currentCompany?.id else { return }
        await model.load(userId: userId, companyId: companyId)
        if !didOpenInitialMode, model.snapshot != nil {
            didOpenInitialMode = true
            if initialMode == .schedule, model.canEditSchedule, let snapshot = model.snapshot { route = .schedule(snapshot) }
        }
    }
}

private enum FinanceSheet: Identifiable {
    case payment
    case schedule(InvoiceFinanceSnapshot)
    var id: String {
        switch self {
        case .payment: "payment"
        case let .schedule(snapshot): "schedule-\(snapshot.invoice.id)"
        }
    }
}

private struct InvoicePaymentReceiptRow: View {
    let receipt: InvoicePaymentReceipt

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(receipt.methodTitle).font(TypographyTokens.headline)
                Spacer(minLength: SpacingTokens.xs)
                CurrencyText(amount: receipt.amount)
                    .foregroundStyle(receipt.amount < 0 ? ColorTokens.error : ColorTokens.primaryText)
            }
            if let date = receipt.recordedAt {
                Text(date.formatted(date: .abbreviated, time: .shortened))
                    .font(TypographyTokens.caption).foregroundStyle(ColorTokens.secondaryText)
            } else {
                Text("Original payment date unavailable")
                    .font(TypographyTokens.caption).foregroundStyle(ColorTokens.secondaryText)
            }
            if let reference = receipt.reference, !reference.isEmpty {
                Text(reference).font(TypographyTokens.subheadline)
            }
            if let notes = receipt.notes, !notes.isEmpty {
                Text(notes).font(TypographyTokens.footnote).foregroundStyle(ColorTokens.secondaryText)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, SpacingTokens.xxs)
    }
}
