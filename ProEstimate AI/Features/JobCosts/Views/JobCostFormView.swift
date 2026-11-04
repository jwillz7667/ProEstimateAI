import SwiftUI

struct JobCostFormView: View {
    let model: JobCostViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft: JobCostDraft
    @State private var receipt: JobCostReceiptAttachment?
    @State private var preparingReceipt = false
    @State private var confirmedCost: JobCostEntry?

    init(model: JobCostViewModel) {
        self.model = model
        _draft = State(initialValue: model.pending.map { JobCostDraft(request: $0.request) } ?? JobCostDraft())
    }

    var body: some View {
        NavigationStack {
            Form {
                if let confirmedCost {
                    Section("Cost saved") {
                        Text(confirmedCost.description).font(TypographyTokens.headline)
                        JobCostMoneyText(amount: confirmedCost.amount, currencyCode: confirmedCost.currencyCode)
                        if let message = model.receiptError {
                            Text(message).fixedSize(horizontal: false, vertical: true)
                        }
                        Text("The cost is already recorded. Attaching a receipt won't create another cost.")
                            .font(TypographyTokens.footnote).foregroundStyle(ColorTokens.secondaryText)
                    }
                } else {
                    detailsSection
                    if model.pending != nil {
                        Section {
                            Text("These details are locked while the previous save is confirmed. Retrying uses the same request to avoid recording the cost twice.")
                                .font(TypographyTokens.footnote).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if confirmedCost?.voidedAt == nil {
                    JobCostReceiptPicker(attachment: $receipt, isPreparing: $preparingReceipt)
                        .disabled(model.isWorking || !model.canEdit)
                }
                if let message = model.errorMessage {
                    Text(message).font(TypographyTokens.footnote).foregroundStyle(ColorTokens.error)
                }
                if confirmedCost == nil, model.pending == nil, !draft.description.isEmpty, let error = draft.validationMessage {
                    Text(error).font(TypographyTokens.footnote).foregroundStyle(ColorTokens.error)
                }
            }
            .navigationTitle(confirmedCost == nil ? "Record job cost" : "Attach receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.disabled(model.isWorking || preparingReceipt)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.isWorking ? "Saving…" : (confirmedCost == nil ? "Save cost" : "Attach receipt")) {
                        Task { await save() }
                    }
                    .disabled(saveDisabled)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .interactiveDismissDisabled(model.isWorking || preparingReceipt)
        }
    }

    private var detailsSection: some View {
        Group {
            Section("Cost") {
                TextField("What was this cost for?", text: $draft.description, axis: .vertical).lineLimit(2 ... 5)
                Picker("Category", selection: $draft.category) {
                    Text("Materials").tag("materials")
                    Text("Labor").tag("labor")
                    Text("Other").tag("other")
                }
                TextField("Currency code", text: $draft.currencyCode)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    .onChange(of: draft.currencyCode) { _, code in draft.currencyCode = code.uppercased() }
                if draft.category == "labor" { Toggle("Calculate from hours", isOn: $draft.useHours) }
                if draft.category == "labor" && draft.useHours {
                    TextField("Hours worked", text: $draft.laborHours).keyboardType(.decimalPad)
                    TextField("Hourly cost", text: $draft.hourlyRate).keyboardType(.decimalPad)
                } else {
                    TextField("Cost amount", text: $draft.amount).keyboardType(.decimalPad)
                }
                DatePicker("Cost date", selection: $draft.recordedAt, in: ...Date(), displayedComponents: [.date])
            }
            Section {
                Text("Record the actual cost paid or incurred for this project. Different currencies remain separate; no exchange rate is applied.")
                    .font(TypographyTokens.footnote).foregroundStyle(ColorTokens.secondaryText)
            }
        }
        .disabled(model.pending != nil || model.isWorking || !model.canEdit)
    }

    private var saveDisabled: Bool {
        if !model.canEdit || model.isWorking || model.journalNeedsAttention || preparingReceipt { return true }
        if confirmedCost != nil { return receipt == nil || confirmedCost?.voidedAt != nil }
        return model.pending == nil && draft.validationMessage != nil
    }

    private func save() async {
        if let confirmedCost, let receipt {
            if await model.attachReceipt(to: confirmedCost, attachment: receipt) { dismiss() }
            return
        }
        if await model.save(draft: draft, receipt: receipt) {
            if model.receiptError != nil, let entry = model.savedEntry, entry.voidedAt == nil {
                confirmedCost = entry
            } else { dismiss() }
        }
    }
}

struct JobCostAttachReceiptView: View {
    let entry: JobCostEntry
    let model: JobCostViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var attachment: JobCostReceiptAttachment?
    @State private var isPreparing = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(entry.description).font(TypographyTokens.headline)
                    JobCostMoneyText(amount: entry.amount, currencyCode: entry.currencyCode)
                    if entry.receiptFilename != nil {
                        Text("The selected receipt will replace this cost's current attachment.")
                            .font(TypographyTokens.footnote).foregroundStyle(ColorTokens.secondaryText)
                    }
                }
                JobCostReceiptPicker(attachment: $attachment, isPreparing: $isPreparing)
                if let error = model.receiptError { Text(error).foregroundStyle(ColorTokens.error) }
            }
            .navigationTitle(entry.receiptFilename == nil ? "Attach receipt" : "Replace receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.disabled(model.isWorking || isPreparing) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.isWorking ? "Attaching…" : "Attach") {
                        guard let attachment else { return }
                        Task { if await model.attachReceipt(to: entry, attachment: attachment) { dismiss() } }
                    }
                    .disabled(attachment == nil || model.isWorking || isPreparing || !model.canEdit)
                }
            }
            .interactiveDismissDisabled(model.isWorking || isPreparing)
        }
    }
}
