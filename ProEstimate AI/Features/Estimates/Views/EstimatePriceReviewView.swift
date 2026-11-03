import SwiftUI

struct EstimatePriceReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @State private var model: EstimatePriceReviewModel

    init(item: EstimateLineItem) {
        _model = State(initialValue: EstimatePriceReviewModel(item: item, service: EstimatePriceReviewService()))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(model.item.name).font(TypographyTokens.headline)
                    LabeledContent("Base cost", value: model.item.unitCost.formatted(.currency(code: "USD")))
                    Text("\(model.item.quantity.formatted()) \(model.item.unit)")
                    Text("Only mark a price checked after comparing it with your supplier, receipt or own rate.")
                        .font(TypographyTokens.footnote).foregroundStyle(ColorTokens.secondaryText)
                }
                Section("Price source") {
                    TextField("Supplier, receipt or company rate", text: $model.form.sourceLabel)
                    TextField("Source link (optional)", text: $model.form.sourceURL)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Toggle("I checked this base price", isOn: $model.form.priceConfirmed)
                }
                Section("Quantity") {
                    Toggle("I checked this quantity", isOn: $model.form.quantityConfirmed)
                    if model.form.quantityConfirmed {
                        TextField("How was it checked?", text: $model.form.quantityBasis, axis: .vertical).lineLimit(2 ... 5)
                        Text("For example: measured on site, counted materials, or checked against the client's plan.")
                            .font(TypographyTokens.footnote).foregroundStyle(ColorTokens.secondaryText)
                    }
                }
                if !model.form.sourceLabel.isEmpty, let validation = model.form.validationMessage {
                    Section { Text(validation).font(TypographyTokens.footnote).foregroundStyle(ColorTokens.secondaryText) }
                }
                if let error = model.errorMessage { Section { Text(error).foregroundStyle(ColorTokens.error) } }
            }
            .disabled(model.isSaving || appState.currentUser?.canEdit != true)
            .navigationTitle("Check price & quantity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(model.isSaving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save check") { Task { if await model.save() { AppEventBus.shared.noteProjectChange(); dismiss() } } }
                        .disabled(model.form.validationMessage != nil || model.isSaving || appState.currentUser?.canEdit != true)
                }
            }
            .interactiveDismissDisabled(model.isSaving)
        }
    }
}
