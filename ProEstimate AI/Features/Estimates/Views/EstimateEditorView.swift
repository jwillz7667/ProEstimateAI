import SwiftUI

struct EstimateEditorView: View {
    let initialNotice: String?
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: EstimateEditorViewModel
    @State private var lineEditor: LineEditorSelection?

    init(estimateId: String, initialNotice: String? = nil) {
        self.initialNotice = initialNotice
        _viewModel = State(initialValue: EstimateEditorViewModel(estimateId: estimateId))
    }

    var body: some View {
        NavigationStack {
            Form {
                if let estimate = viewModel.estimate {
                    documentSection(estimate)
                    if let initialNotice {
                        Section { Text(initialNotice).font(TypographyTokens.subheadline) }
                    }
                    errorSection
                    itemsSection
                    totalsSection(estimate)
                    documentNotes(estimate)
                } else if viewModel.isLoading {
                    ProgressView("Loading estimate…")
                } else {
                    errorSection
                }
            }
            .navigationTitle("Estimate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .disabled(viewModel.isSaving)
                }
            }
            .refreshable { await viewModel.load() }
            .task { await viewModel.load() }
            .sheet(item: $lineEditor) { selection in
                EstimateLineEditorSheet(model: viewModel, selection: selection)
            }
            .interactiveDismissDisabled(viewModel.isSaving)
        }
    }

    private func documentSection(_ estimate: Estimate) -> some View {
        Section {
            VStack(alignment: .leading, spacing: SpacingTokens.xs) {
                Text(estimate.title ?? estimate.estimateNumber)
                    .font(TypographyTokens.title3)
                Text("\(estimate.estimateNumber) · Version \(estimate.version)")
                    .font(TypographyTokens.subheadline)
                    .foregroundStyle(ColorTokens.secondaryText)
                Text(estimate.status.rawValue.capitalized)
                    .font(TypographyTokens.caption.weight(.semibold))
                if !estimate.isEditable {
                    Text("This estimate is read-only because it is no longer a draft. You can still review every item and its saved total.")
                        .font(TypographyTokens.footnote)
                        .foregroundStyle(ColorTokens.secondaryText)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var errorSection: some View {
        if let message = viewModel.errorMessage {
            Section {
                Text(message)
                    .font(TypographyTokens.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Refresh estimate") { Task { await viewModel.load() } }
                    .disabled(viewModel.isLoading || viewModel.isSaving)
            }
        }
    }

    private var itemsSection: some View {
        Section {
            if viewModel.lineItems.isEmpty {
                Text("Add materials, labor or other costs to build this estimate. Nothing is charged for manual edits.")
                    .font(TypographyTokens.subheadline)
                    .foregroundStyle(ColorTokens.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(viewModel.lineItems) { item in
                if viewModel.canEdit {
                    Button {
                        lineEditor = LineEditorSelection(itemId: item.id, form: EstimateLineItemForm(item: item))
                    } label: {
                        lineItemRow(item, editable: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Edit quantity, unit cost, markup or tax")
                } else {
                    lineItemRow(item, editable: false)
                }
            }
            if viewModel.estimate?.isEditable == true {
                Button {
                    lineEditor = LineEditorSelection(itemId: nil, form: viewModel.newItemForm())
                } label: {
                    Label("Add line item", systemImage: "plus.circle")
                }
                .disabled(!viewModel.canEdit)
            }
        } header: {
            Text("Line items")
        } footer: {
            Text(viewModel.requiresRefresh
                ? "Refresh before making changes. Saved totals are shown until the document is current."
                : "Amounts below are calculated and saved by the server after each change.")
        }
    }

    private func lineItemRow(_ item: EstimateLineItem, editable: Bool) -> some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.name)
                    .font(TypographyTokens.headline)
                    .foregroundStyle(ColorTokens.primaryText)
                Spacer(minLength: SpacingTokens.xs)
                if editable {
                    Image(systemName: "pencil")
                        .font(.footnote)
                        .foregroundStyle(ColorTokens.secondaryText)
                        .accessibilityHidden(true)
                }
            }
            Text(item.category.rawValue.capitalized)
                .font(TypographyTokens.caption)
                .foregroundStyle(ColorTokens.secondaryText)
            if let description = item.description, !description.isEmpty {
                Text(description)
                    .font(TypographyTokens.subheadline)
                    .foregroundStyle(ColorTokens.secondaryText)
            }
            HStack {
                Text("\(item.quantity.formatted()) \(item.unit) × ")
                CurrencyText(amount: item.unitCost, font: TypographyTokens.moneyCaption)
                Spacer(minLength: 0)
            }
            .font(TypographyTokens.caption)
            .foregroundStyle(ColorTokens.secondaryText)
            Text("Markup \(item.markupPercent.formatted())% · Tax \(item.taxRate.formatted())%")
                .font(TypographyTokens.caption)
                .foregroundStyle(ColorTokens.secondaryText)
            HStack {
                Text("Line subtotal")
                    .font(TypographyTokens.caption)
                    .foregroundStyle(ColorTokens.secondaryText)
                Spacer()
                CurrencyText(amount: item.lineTotal)
                    .foregroundStyle(ColorTokens.primaryText)
            }
        }
        .padding(.vertical, SpacingTokens.xxs)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    private func totalsSection(_ estimate: Estimate) -> some View {
        Section("Saved totals") {
            moneyRow("Materials", estimate.subtotalMaterials)
            moneyRow("Labor", estimate.subtotalLabor)
            moneyRow("Other", estimate.subtotalOther)
            moneyRow("Tax", estimate.taxAmount)
            if estimate.discountAmount > 0 { moneyRow("Discount", -estimate.discountAmount) }
            if let contingency = estimate.contingencyAmount, contingency > 0 {
                moneyRow("Contingency", contingency)
            }
            moneyRow("Total", estimate.totalAmount)
                .fontWeight(.semibold)
        }
    }

    private func moneyRow(_ title: String, _ value: Decimal) -> some View {
        LabeledContent(title) { CurrencyText(amount: value) }
    }

    @ViewBuilder
    private func documentNotes(_ estimate: Estimate) -> some View {
        if let assumptions = estimate.assumptions, !assumptions.isEmpty {
            Section("Assumptions") { Text(assumptions) }
        }
        if let exclusions = estimate.exclusions, !exclusions.isEmpty {
            Section("Exclusions") { Text(exclusions) }
        }
        if let notes = estimate.notes, !notes.isEmpty {
            Section("Notes") { Text(notes) }
        }
    }
}

private struct LineEditorSelection: Identifiable {
    let id = UUID()
    let itemId: String?
    let form: EstimateLineItemForm
}

private struct EstimateLineEditorSheet: View {
    let model: EstimateEditorViewModel
    let selection: LineEditorSelection
    @Environment(\.dismiss) private var dismiss
    @State private var form: EstimateLineItemForm
    @State private var showDiscard = false
    @State private var showRemove = false

    init(model: EstimateEditorViewModel, selection: LineEditorSelection) {
        self.model = model
        self.selection = selection
        _form = State(initialValue: selection.form)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Item") {
                    Picker("Category", selection: $form.category) {
                        ForEach(EstimateLineItem.Category.allCases, id: \.self) { category in
                            Text(category.rawValue.capitalized).tag(category)
                        }
                    }
                    TextField("Item name", text: $form.name, axis: .vertical)
                        .lineLimit(1 ... 4)
                    TextField("Description (optional)", text: $form.details, axis: .vertical)
                        .lineLimit(3 ... 8)
                }
                Section {
                    decimalField("Quantity", text: $form.quantity)
                    LabeledContent("Unit") {
                        TextField("each, hours, sq ft…", text: $form.unit)
                            .multilineTextAlignment(.trailing)
                    }
                    decimalField("Unit cost", text: $form.unitCost)
                    decimalField("Markup (%)", text: $form.markupPercent)
                    decimalField("Tax (%)", text: $form.taxPercent)
                } header: {
                    Text("Pricing")
                } footer: {
                    Text("Enter percentages as shown: 8.25 means 8.25%. The saved estimate total updates after you save.")
                }
                if let message = model.errorMessage {
                    Section {
                        Text(message)
                        if model.requiresRefresh {
                            Button("Review saved estimate") {
                                Task { await model.load(); dismiss() }
                            }
                        }
                    }
                }
                if selection.itemId != nil {
                    Section {
                        Button("Remove line item", role: .destructive) { showRemove = true }
                            .disabled(!model.canEdit)
                    }
                }
            }
            .disabled(model.isSaving)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(selection.itemId == nil ? "Add line item" : "Edit line item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if form != selection.form { showDiscard = true } else { dismiss() }
                    }
                    .disabled(model.isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            if await model.save(itemId: selection.itemId, form: form) { dismiss() }
                        }
                    }
                    .disabled(!model.canEdit)
                }
            }
            .interactiveDismissDisabled(model.isSaving || form != selection.form)
            .confirmationDialog("Discard your changes?", isPresented: $showDiscard, titleVisibility: .visible) {
                Button("Discard changes", role: .destructive) { dismiss() }
                Button("Keep editing", role: .cancel) {}
            }
            .confirmationDialog("Remove this line item?", isPresented: $showRemove, titleVisibility: .visible) {
                Button("Remove line item", role: .destructive) {
                    if let itemId = selection.itemId {
                        Task { if await model.remove(itemId: itemId) { dismiss() } }
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private func decimalField(_ title: String, text: Binding<String>) -> some View {
        LabeledContent(title) {
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .accessibilityLabel(title)
        }
    }
}
