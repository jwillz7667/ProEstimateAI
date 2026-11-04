import SwiftUI

struct CreateChangeOrderView: View {
    let estimate: Estimate
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var model = ChangeOrderMutationModel(
        service: ChangeOrderService(), journal: ChangeOrderJournal())
    @State private var title = ""
    @State private var reason = ""
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Amend approved work").font(.headline)
                    Text(
                        "A change order copies the approved contract into a separate draft. The customer reviews the original and revised totals before signing. Existing quotes, invoices and cash receipts stay in the history."
                    )
                    .font(.subheadline).foregroundStyle(.secondary)
                    LabeledContent(
                        "Approved version", value: "\(estimate.estimateNumber) · v\(estimate.version)")
                    LabeledContent("Current contract price") { CurrencyText(amount: estimate.totalAmount) }
                }
                if let result = model.result {
                    Section {
                        NavigationLink("Open saved change order") {
                            ChangeOrderDetailView(orderId: result.id)
                        }
                    }
                } else {
                    Section("Describe the change") {
                        TextField("Change order title", text: $title)
                        TextField("What is changing and why?", text: $reason, axis: .vertical).lineLimit(
                            3...8)
                    }.disabled(model.pending != nil || model.isWorking || !model.isReady)
                    if let pending = model.pending, let request = pending.create {
                        Section("Saved request awaiting confirmation") {
                            Text(request.title).font(.headline)
                            Text(request.reason)
                            Text(
                                "Retry uses the same saved request, so a lost response won't create another change order."
                            ).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    Section {
                        Button(
                            model.pending == nil ? "Create change order draft" : "Retry saved change order"
                        ) {
                            Task { await model.create(title: title, reason: reason) }
                        }.disabled(!model.isReady || model.isWorking || appState.currentUser?.canEdit != true)
                    }
                }
                if model.isWorking { ProgressView("Saving change order…") }
                if let error = model.errorMessage { Section { Text(error).font(.footnote) } }
            }
            .navigationTitle("Change order").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }.disabled(model.isWorking)
                }
            }
            .task {
                guard let user = appState.currentUser, let companyId = appState.currentCompany?.id else {
                    return
                }
                await model.restore(
                    scope: EstimateDraftScope(userId: user.id, companyId: companyId), resourceId: estimate.id)
            }
            .interactiveDismissDisabled(model.isWorking)
        }
    }
}

struct ChangeOrderListView: View {
    let projectId: String
    @State private var orders: [ChangeOrder] = []
    @State private var loading = false
    @State private var error: String?
    var body: some View {
        List {
            if loading && orders.isEmpty { ProgressView("Loading change orders…") }
            if let error { Text(error).font(.footnote) }
            if !loading && orders.isEmpty && error == nil {
                ContentUnavailableView(
                    "No change orders", systemImage: "doc.badge.plus",
                    description: Text(
                        "Open an approved estimate and choose Create change order when the agreed scope or price changes."
                    ))
            }
            ForEach(orders) { order in
                NavigationLink {
                    ChangeOrderDetailView(orderId: order.id)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(order.title).font(.headline)
                        Text(order.status.capitalized).font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Text("Contract change")
                            Spacer()
                            CurrencyText(amount: order.comparison.changeAmount)
                        }.font(.subheadline)
                    }.padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Change orders")
        .task { await load() }.refreshable { await load() }
    }
    private func load() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            orders = try await ChangeOrderService().list(projectId: projectId)
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

struct ChangeOrderDetailView: View {
    let orderId: String
    @Environment(AppState.self) private var appState
    @Environment(PaywallPresenter.self) private var paywall
    @Environment(FeatureGateCoordinator.self) private var featureGate
    @State private var order: ChangeOrder?
    @State private var error: String?
    @State private var loading = false
    @State private var replacementSource: Estimate?
    @State private var firstInvoice: Invoice?
    @State private var converting = false
    @State private var editor = false
    @State private var applyConfirmation = false
    @State private var model = ChangeOrderMutationModel(
        service: ChangeOrderService(), journal: ChangeOrderJournal())
    var body: some View {
        Form {
            if let order {
                Section {
                    Text(order.title).font(.title3.weight(.semibold))
                    Text(order.status.capitalized).font(.caption.weight(.semibold))
                    Text(order.reason).font(.subheadline)
                }
                ChangeOrderComparisonSection(comparison: order.comparison)
                Section("Next step") {
                    Button(
                        order.estimate.isEditable
                            ? "Edit amended scope & review" : "View change order document"
                    ) { editor = true }
                    if ["changes_requested", "declined"].contains(order.status) {
                        Button("Prepare replacement change order") { Task { await replace(order) } }
                            .disabled(appState.currentUser?.canEdit != true)
                        Text(
                            "The replacement starts from the last approved baseline and gets a new customer review. This sent document remains unchanged."
                        ).font(.footnote).foregroundStyle(.secondary)
                    }
                    if order.status == "approved" && order.rootInvoiceId == nil {
                        Text("This change will be included in the first invoice at the full revised price.")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button(converting ? "Creating invoice…" : "Create first contract invoice") {
                            Task { await createFirstInvoice(order) }
                        }
                        .disabled(converting || appState.currentUser?.canEdit != true)
                    }
                    if order.canApply || model.pending != nil {
                        Button(model.pending == nil ? "Apply approved change" : "Retry saved apply request") {
                            applyConfirmation = true
                        }
                        .disabled(model.isWorking || !model.isReady || appState.currentUser?.canEdit != true)
                        Text(
                            "A positive change creates an invoice for only the extra amount. A negative change creates a credit note. Applying never charges or refunds a card."
                        ).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if let note = order.creditNote {
                    Section("Credit note · \(note.creditNumber)") {
                        LabeledContent("Issued contract credit") { CurrencyText(amount: note.amount) }
                        LabeledContent("Applied to invoice balances") {
                            CurrencyText(amount: note.allocatedAmount)
                        }
                        LabeledContent("Available for this contract") {
                            CurrencyText(amount: note.availableAmount)
                        }
                        Text(
                            "Credit reduces the amount owed. It is separate from money received and does not automatically refund a payment."
                        ).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if !order.invoices.isEmpty {
                    Section("Additional invoices") {
                        ForEach(order.invoices) { invoice in
                            NavigationLink {
                                InvoiceDetailView(invoiceId: invoice.id)
                            } label: {
                                LabeledContent(invoice.invoiceNumber) {
                                    CurrencyText(
                                        amount: invoice.totalAmount,
                                        currencyCode: invoice.currencyCode ?? "USD")
                                }
                            }
                        }
                    }
                }
                if let rootInvoiceId = order.rootInvoiceId {
                    Section {
                        NavigationLink("Original contract invoice") {
                            InvoiceDetailView(invoiceId: rootInvoiceId)
                        }
                    }
                }
            } else if loading {
                ProgressView("Loading change order…")
            }
            if model.isWorking { ProgressView("Applying approved change…") }
            if let message = model.errorMessage ?? error { Section { Text(message).font(.footnote) } }
        }
        .navigationTitle("Change order").navigationBarTitleDisplayMode(.inline)
        .task { await load() }.refreshable { await load() }
        .sheet(isPresented: $editor, onDismiss: { Task { await load() } }) {
            if let order { EstimateEditorView(estimateId: order.estimateId) }
        }
        .sheet(item: $replacementSource) { source in CreateChangeOrderView(estimate: source) }
        .sheet(item: $firstInvoice, onDismiss: { Task { await load() } }) { invoice in
            NavigationStack { InvoiceDetailView(invoiceId: invoice.id, isPresentedInSheet: true) }
        }
        .confirmationDialog(
            "Apply this approved change?", isPresented: $applyConfirmation, titleVisibility: .visible
        ) {
            Button("Apply approved change") { Task { await apply() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This records only the approved difference. Existing invoices and cash receipts stay unchanged."
            )
        }
    }
    private func load() async {
        guard !loading, !model.isWorking else { return }
        loading = true
        defer { loading = false }
        do {
            order = try await ChangeOrderService().get(id: orderId)
            error = nil
            if let user = appState.currentUser, let companyId = appState.currentCompany?.id {
                await model.restore(
                    scope: EstimateDraftScope(userId: user.id, companyId: companyId), resourceId: orderId)
            }
        } catch { self.error = error.localizedDescription }
    }
    private func replace(_ order: ChangeOrder) async {
        do { replacementSource = try await LiveEstimateService().getEstimate(id: order.baseEstimateId) } catch
        { self.error = error.localizedDescription }
    }
    private func createFirstInvoice(_ order: ChangeOrder) async {
        switch featureGate.guardCreateInvoice() {
        case .allowed: break
        case .blocked(let decision):
            paywall.present(decision)
            return
        }
        guard !converting else { return }
        converting = true
        defer { converting = false }
        do {
            firstInvoice = try await LiveInvoiceService().convertEstimate(
                estimateId: order.estimateId, request: .faithful)
            error = nil
        } catch {
            self.error = error.localizedDescription
            if let apiError = error as? APIError, case .paywall(let decision) = apiError {
                paywall.present(decision)
            }
        }
    }
    private func apply() async {
        if model.pending == nil {
            switch featureGate.guardCreateInvoice() {
            case .allowed: break
            case .blocked(let decision):
                paywall.present(decision)
                return
            }
        }
        await model.apply()
        if let result = model.result { order = result }
        if let apiError = model.lastError as? APIError, case .paywall(let decision) = apiError {
            paywall.present(decision)
        }
    }
}

struct ChangeOrderComparisonSection: View {
    let comparison: ChangeOrderComparison
    private var billingExplanation: String {
        switch comparison.billingEffect {
        case "included_in_first_invoice": "The first invoice will include the full revised contract price once."
        case "credit_note": "This change reduces the contract price. Applying it issues a credit note; it does not refund cash automatically."
        case "no_price_change": "The scope changes without an additional amount to collect."
        default: "Additional billing uses only the approved difference, while the revised document shows the full agreed scope."
        }
    }
    var body: some View {
        Section("Contract comparison") {
            LabeledContent("Previous approved price") { CurrencyText(amount: comparison.baseTotal) }
            LabeledContent("Revised contract price") { CurrencyText(amount: comparison.newTotal) }
            LabeledContent(comparison.changeAmount < 0 ? "Contract credit" : "Additional amount") {
                CurrencyText(amount: abs(comparison.changeAmount))
            }.font(.headline)
            if comparison.taxDelta != 0 {
                LabeledContent("Tax change") { CurrencyText(amount: comparison.taxDelta) }
            }
            if comparison.discountDelta != 0 {
                LabeledContent("Discount change") { CurrencyText(amount: comparison.discountDelta) }
            }
            Text(
                "Compared with \(comparison.baseEstimateNumber), version \(comparison.baseVersion). \(billingExplanation)"
            ).font(.footnote).foregroundStyle(.secondary)
        }
    }
}
