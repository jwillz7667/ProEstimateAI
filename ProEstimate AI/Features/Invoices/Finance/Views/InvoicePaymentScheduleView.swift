import SwiftUI

struct InvoicePaymentScheduleView: View {
    let model: InvoiceFinanceViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @State private var form: InvoicePaymentScheduleForm

    init(model: InvoiceFinanceViewModel, snapshot: InvoiceFinanceSnapshot) {
        self.model = model
        _form = State(initialValue: InvoicePaymentScheduleForm(snapshot: snapshot))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Invoice total") { CurrencyText(amount: form.expectedTotal, currencyCode: model.snapshot?.invoice.currencyCode ?? "USD") }
                    Text("Break the total into a deposit and later payments. Saving a schedule requests payments; it does not record money received.")
                        .font(TypographyTokens.footnote).fixedSize(horizontal: false, vertical: true)
                    Menu("Use a deposit split") {
                        ForEach([25, 30, 50], id: \.self) { percent in
                            Button("\(percent)% deposit") { form.useDeposit(percent: percent) }
                        }
                    }
                }
                ForEach($form.installments) { $installment in
                    Section {
                        TextField("Payment name", text: $installment.title)
                        TextField("Amount", text: $installment.amount).keyboardType(.decimalPad)
                        Toggle("Due date", isOn: $installment.hasDueDate)
                        if installment.hasDueDate {
                            DatePicker("Due", selection: $installment.dueDate, displayedComponents: [.date])
                        }
                        if form.installments.count > 1 {
                            Button("Remove payment", role: .destructive) {
                                form.installments.removeAll { $0.id == installment.id }
                            }
                        }
                    }
                }
                if form.installments.count < 24 {
                    Button("Add milestone payment") { form.installments.append(InvoiceInstallmentDraft()) }
                }
                if let validation { Text(validation).font(TypographyTokens.footnote).foregroundStyle(ColorTokens.error) }
                if let message = model.errorMessage {
                    Section {
                        Text(message).fixedSize(horizontal: false, vertical: true)
                        if model.scheduleNeedsRefresh {
                            Button("Reload saved schedule") { Task { await reload() } }
                                .disabled(model.isLoading || model.isWorking)
                            Text("Reloading replaces this form with the saved schedule.")
                                .font(TypographyTokens.footnote).foregroundStyle(ColorTokens.secondaryText)
                        }
                    }
                }
            }
            .disabled(model.isWorking)
            .navigationTitle("Payment schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(model.isWorking) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.isWorking ? "Saving…" : "Save") {
                        Task { if await model.updateSchedule(form) { dismiss() } }
                    }
                    .disabled(validation != nil || !model.canEditSchedule || appState.currentUser?.canEdit != true)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .interactiveDismissDisabled(model.isWorking)
        }
    }

    private var validation: String? {
        guard let invoice = model.snapshot?.invoice else { return "Refresh this invoice before changing its schedule." }
        do { _ = try form.request(invoice: invoice); return nil }
        catch { return error.localizedDescription }
    }

    private func reload() async {
        guard let userId = appState.currentUser?.id, let companyId = appState.currentCompany?.id else { return }
        await model.load(userId: userId, companyId: companyId)
        if let snapshot = model.snapshot, !model.scheduleNeedsRefresh { form = InvoicePaymentScheduleForm(snapshot: snapshot) }
    }
}
