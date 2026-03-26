import SwiftUI

struct LineItemEditSheet: View {
    @State var draft: LineItemDraft
    let onSave: (LineItemDraft) -> Void
    let onCancel: () -> Void

    @State private var quantityText: String = ""
    @State private var unitCostText: String = ""
    @State private var markupText: String = ""
    @State private var taxRateText: String = ""

    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case name, description, quantity, unitCost, markup, taxRate
    }

    var body: some View {
        NavigationStack {
            Form {
                basicInfoSection
                pricingSection
                markupAndTaxSection
                lineTotalSection
            }
            .navigationTitle(isNewItem ? "Add Line Item" : "Edit Line Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        syncTextFieldsToDraft()
                        onSave(draft)
                    }
                    .fontWeight(.semibold)
                    .disabled(!draft.isValid)
                }
            }
            .onAppear {
                initializeTextFields()
            }
        }
    }

    // MARK: - Sections

    private var basicInfoSection: some View {
        Section("Item Details") {
            TextField("Item Name", text: $draft.name)
                .focused($focusedField, equals: .name)

            TextField("Description (optional)", text: $draft.description, axis: .vertical)
                .focused($focusedField, equals: .description)
                .lineLimit(2...4)

            Picker("Category", selection: $draft.category) {
                ForEach(EstimateLineItem.Category.allCases, id: \.self) { category in
                    Text(category.rawValue.capitalized).tag(category)
                }
            }
        }
    }

    private var pricingSection: some View {
        Section("Pricing") {
            HStack {
                Text("Quantity")
                Spacer()
                TextField("Qty", text: $quantityText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    .focused($focusedField, equals: .quantity)
                    .onChange(of: quantityText) { _, newValue in
                        if let value = Decimal(string: newValue), value >= 0 {
                            draft.quantity = value
                        }
                    }

                Stepper("", value: Binding(
                    get: { NSDecimalNumber(decimal: draft.quantity).intValue },
                    set: { draft.quantity = Decimal($0); quantityText = "\($0)" }
                ), in: 1...9999)
                .labelsHidden()
            }

            Picker("Unit", selection: $draft.unit) {
                ForEach(LineItemUnit.allCases) { unit in
                    Text(unit.displayName).tag(unit)
                }
            }

            HStack {
                Text("Unit Cost")
                Spacer()
                Text("$")
                    .foregroundStyle(.secondary)
                TextField("0.00", text: $unitCostText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
                    .focused($focusedField, equals: .unitCost)
                    .onChange(of: unitCostText) { _, newValue in
                        if let value = Decimal(string: newValue), value >= 0 {
                            draft.unitCost = value
                        }
                    }
            }
        }
    }

    private var markupAndTaxSection: some View {
        Section("Markup & Tax") {
            VStack(alignment: .leading, spacing: SpacingTokens.xs) {
                HStack {
                    Text("Markup")
                    Spacer()
                    TextField("0", text: $markupText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                        .focused($focusedField, equals: .markup)
                        .onChange(of: markupText) { _, newValue in
                            if let value = Decimal(string: newValue), value >= 0 {
                                draft.markupPercent = value
                            }
                        }
                    Text("%")
                        .foregroundStyle(.secondary)
                }

                Slider(
                    value: Binding(
                        get: { NSDecimalNumber(decimal: draft.markupPercent).doubleValue },
                        set: {
                            draft.markupPercent = Decimal($0)
                            markupText = String(format: "%.0f", $0)
                        }
                    ),
                    in: 0...100,
                    step: 5
                )
                .tint(ColorTokens.primaryOrange)
            }

            HStack {
                Text("Tax Rate")
                Spacer()
                TextField("0.00", text: $taxRateText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
                    .focused($focusedField, equals: .taxRate)
                    .onChange(of: taxRateText) { _, newValue in
                        if let value = Decimal(string: newValue), value >= 0, value <= 100 {
                            draft.taxRate = value
                        }
                    }
                Text("%")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var lineTotalSection: some View {
        Section {
            VStack(spacing: SpacingTokens.xs) {
                totalRow(label: "Base Cost", amount: draft.baseCost)
                totalRow(label: "Markup (\(formattedPercent(draft.markupPercent))%)", amount: draft.markupAmount)
                totalRow(label: "Tax (\(formattedPercent(draft.taxRate))%)", amount: draft.taxAmount)
                Divider()
                HStack {
                    Text("Line Total")
                        .font(TypographyTokens.headline)
                    Spacer()
                    CurrencyText(amount: draft.lineTotal, font: TypographyTokens.moneyMedium)
                }
            }
        } header: {
            Text("Computed Total")
        }
    }

    // MARK: - Helpers

    private var isNewItem: Bool {
        draft.name.isEmpty && draft.unitCost == 0
    }

    private func totalRow(label: String, amount: Decimal) -> some View {
        HStack {
            Text(label)
                .font(TypographyTokens.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            CurrencyText(amount: amount, font: TypographyTokens.moneySmall)
                .foregroundStyle(.secondary)
        }
    }

    private func initializeTextFields() {
        quantityText = formatDecimalForField(draft.quantity)
        unitCostText = formatDecimalForField(draft.unitCost)
        markupText = formatDecimalForField(draft.markupPercent)
        taxRateText = formatDecimalForField(draft.taxRate)
    }

    private func syncTextFieldsToDraft() {
        if let q = Decimal(string: quantityText) { draft.quantity = q }
        if let c = Decimal(string: unitCostText) { draft.unitCost = c }
        if let m = Decimal(string: markupText) { draft.markupPercent = m }
        if let t = Decimal(string: taxRateText) { draft.taxRate = t }
    }

    private func formatDecimalForField(_ value: Decimal) -> String {
        let number = NSDecimalNumber(decimal: value)
        if value == Decimal(number.intValue) {
            return "\(number.intValue)"
        }
        return "\(number.doubleValue)"
    }

    private func formattedPercent(_ value: Decimal) -> String {
        let number = NSDecimalNumber(decimal: value)
        if value == Decimal(number.intValue) {
            return "\(number.intValue)"
        }
        return String(format: "%.1f", number.doubleValue)
    }
}

// MARK: - Preview

#Preview {
    LineItemEditSheet(
        draft: LineItemDraft(from: .sample),
        onSave: { _ in },
        onCancel: {}
    )
}
