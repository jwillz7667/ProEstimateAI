import SwiftUI

struct EstimateDocumentFormView: View {
    let model: EstimateEditorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var form: EstimateDocumentForm

    init(model: EstimateEditorViewModel, estimate: Estimate) {
        self.model = model
        _form = State(initialValue: EstimateDocumentForm(estimate: estimate))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Estimate") {
                    TextField("Title (optional)", text: $form.title, axis: .vertical)
                        .lineLimit(1 ... 4)
                    TextField("Scope and notes", text: $form.notes, axis: .vertical)
                        .lineLimit(5 ... 12)
                }
                Section("Scope boundaries") {
                    TextField("Assumptions", text: $form.assumptions, axis: .vertical).lineLimit(3 ... 10)
                    TextField("Exclusions", text: $form.exclusions, axis: .vertical).lineLimit(3 ... 10)
                }
                Section {
                    LabeledContent("Discount") {
                        TextField("0.00", text: $form.discount)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    Toggle("Estimate expires", isOn: $form.hasValidUntil)
                    if form.hasValidUntil {
                        DatePicker("Valid until", selection: $form.validUntil, displayedComponents: [.date, .hourAndMinute])
                    }
                } header: {
                    Text("Pricing and validity")
                } footer: {
                    Text("The discount applies to the full estimate. Review the updated total after saving.")
                }
                if let message = model.errorMessage {
                    Section {
                        Text(message).fixedSize(horizontal: false, vertical: true)
                        if model.requiresRefresh {
                            Button("Reload saved details") {
                                Task {
                                    await model.load()
                                    if let estimate = model.estimate, !model.requiresRefresh {
                                        form = EstimateDocumentForm(estimate: estimate)
                                    }
                                }
                            }
                            .disabled(model.isLoading || model.isSaving)
                            Text("Reloading replaces this form with the saved document so you can confirm what was applied.")
                                .font(TypographyTokens.footnote)
                                .foregroundStyle(ColorTokens.secondaryText)
                        }
                    }
                }
            }
            .disabled(model.isSaving)
            .navigationTitle("Estimate details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(model.isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.isSaving ? "Saving…" : "Save") {
                        Task { if await model.saveDocument(form: form) { dismiss() } }
                    }
                    .disabled(!model.canEdit)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .interactiveDismissDisabled(model.isSaving)
        }
    }
}
