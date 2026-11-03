import SwiftUI

struct InvoiceReceivedPaymentFormView: View {
    let model: InvoiceFinanceViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @State private var form: InvoiceReceivedPaymentForm
    @State private var confirmRecord = false

    init(model: InvoiceFinanceViewModel) {
        self.model = model
        _form = State(initialValue: model.pendingPayment.map { InvoiceReceivedPaymentForm(request: $0.request) } ?? InvoiceReceivedPaymentForm())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Record money you have already received. This does not charge your client.")
                        .font(TypographyTokens.subheadline).fixedSize(horizontal: false, vertical: true)
                    if let invoice = model.snapshot?.invoice {
                        LabeledContent("Outstanding") { CurrencyText(amount: invoice.amountDue) }
                    }
                }
                Section("Payment received") {
                    TextField("Amount", text: $form.amount).keyboardType(.decimalPad)
                    Picker("Method", selection: $form.method) {
                        ForEach(ReceivedPaymentMethod.allCases) { method in Text(method.title).tag(method) }
                    }
                    TextField("Check or transfer reference (optional)", text: $form.reference)
                    TextField("Internal notes (optional)", text: $form.notes, axis: .vertical).lineLimit(2 ... 6)
                    DatePicker("Received", selection: $form.recordedAt, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                }
                .disabled(model.pendingPayment != nil || model.isWorking)
                if model.pendingPayment != nil {
                    Section {
                        Text("These details are locked while the previous record is confirmed. A retry uses the same request and cannot record the payment twice.")
                            .font(TypographyTokens.footnote).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let message = model.errorMessage {
                    Section {
                        Text(message).fixedSize(horizontal: false, vertical: true)
                        Button("Refresh receipt history") { Task { await refresh() } }
                            .disabled(model.isLoading || model.isWorking)
                    }
                }
                if model.pendingPayment == nil, !form.amount.isEmpty, let validation {
                    Text(validation).font(TypographyTokens.footnote).foregroundStyle(ColorTokens.error)
                }
            }
            .navigationTitle("Record payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.disabled(model.isWorking) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.isWorking ? "Recording…" : (model.pendingPayment == nil ? "Record" : "Retry same payment")) {
                        if model.pendingPayment == nil { confirmRecord = true }
                        else { Task { if await model.retryPendingPayment() { dismiss() } } }
                    }
                    .disabled(model.isWorking || model.isLoading || model.journalNeedsAttention || appState.currentUser?.canEdit != true || (model.pendingPayment == nil && validation != nil))
                }
            }
            .confirmationDialog("Record this received payment?", isPresented: $confirmRecord, titleVisibility: .visible) {
                Button("Record received payment") { Task { if await model.record(form: form) { dismiss() } } }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Confirm the amount, method and date match money already received from your client.") }
            .scrollDismissesKeyboard(.interactively)
            .interactiveDismissDisabled(model.isWorking)
        }
    }

    private var validation: String? {
        guard let invoice = model.snapshot?.invoice else { return "Refresh the invoice before recording a payment." }
        do { _ = try form.request(invoice: invoice); return nil }
        catch { return error.localizedDescription }
    }

    private func refresh() async {
        guard let userId = appState.currentUser?.id, let companyId = appState.currentCompany?.id else { return }
        let hadPending = model.pendingPayment != nil
        await model.load(userId: userId, companyId: companyId)
        if hadPending, model.pendingPayment == nil, !model.journalNeedsAttention { dismiss() }
    }
}
