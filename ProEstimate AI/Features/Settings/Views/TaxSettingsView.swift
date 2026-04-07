import SwiftUI

struct TaxSettingsView: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        Form {
            // Default Tax Rate
            Section {
                VStack(alignment: .leading, spacing: SpacingTokens.xs) {
                    HStack {
                        Text("Default Tax Rate")
                        Spacer()
                        TextField("0.00", text: $viewModel.taxRateText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                            .onChange(of: viewModel.taxRateText) { _, newValue in
                                if let value = Decimal(string: newValue), value >= 0, value <= 100 {
                                    viewModel.defaultTaxRate = value
                                }
                            }
                        Text("%")
                            .foregroundStyle(.secondary)
                    }

                    Slider(
                        value: Binding(
                            get: { NSDecimalNumber(decimal: viewModel.defaultTaxRate).doubleValue },
                            set: {
                                viewModel.defaultTaxRate = Decimal($0)
                                viewModel.taxRateText = String(format: "%.2f", $0)
                            }
                        ),
                        in: 0...15,
                        step: 0.25
                    )
                    .tint(ColorTokens.primaryOrange)
                }
            } header: {
                Text("Default Rate")
            } footer: {
                Text("This rate is applied to new line items by default. You can override per-item in the estimate editor.")
            }

            // Tax-Inclusive Pricing
            Section {
                Toggle(isOn: $viewModel.taxInclusivePricing) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tax-Inclusive Pricing")
                        Text("Display prices with tax included")
                            .font(TypographyTokens.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(ColorTokens.primaryOrange)
            } footer: {
                Text("When enabled, line item prices shown to clients will include tax. The tax breakdown is still shown separately on invoices.")
            }

            // Category Overrides
            Section("Category Overrides") {
                categoryOverrideRow(
                    category: "Materials",
                    icon: "shippingbox",
                    color: ColorTokens.primaryOrange,
                    rate: viewModel.defaultTaxRate
                )

                categoryOverrideRow(
                    category: "Labor",
                    icon: "hammer",
                    color: .blue,
                    rate: 0
                )

                categoryOverrideRow(
                    category: "Other",
                    icon: "ellipsis.circle",
                    color: .purple,
                    rate: viewModel.defaultTaxRate
                )
            }

            // Preview
            Section("Preview") {
                taxPreview
            }

            // Save
            Section {
                PrimaryCTAButton(
                    title: "Save Tax Settings",
                    icon: "checkmark.circle",
                    isLoading: viewModel.isSaving
                ) {
                    Task { await viewModel.saveTaxSettings() }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Tax Settings")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Success", isPresented: .init(
            get: { viewModel.successMessage != nil },
            set: { if !$0 { viewModel.successMessage = nil } }
        )) {
            Button("OK", role: .cancel) { viewModel.successMessage = nil }
        } message: {
            Text(viewModel.successMessage ?? "")
        }
    }

    // MARK: - Subviews

    private func categoryOverrideRow(
        category: String,
        icon: String,
        color: Color,
        rate: Decimal
    ) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 24)

            Text(category)
                .font(TypographyTokens.body)

            Spacer()

            Text("\(NSDecimalNumber(decimal: rate).doubleValue, specifier: "%.2f")%")
                .font(TypographyTokens.moneySmall)
                .foregroundStyle(.secondary)
        }
    }

    private var taxPreview: some View {
        VStack(spacing: SpacingTokens.xs) {
            HStack {
                Text("Subtotal")
                    .font(TypographyTokens.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("$1,000.00")
                    .font(TypographyTokens.moneySmall)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Tax (\(NSDecimalNumber(decimal: viewModel.defaultTaxRate).doubleValue, specifier: "%.2f")%)")
                    .font(TypographyTokens.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(taxPreviewAmount)
                    .font(TypographyTokens.moneySmall)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Text("Total")
                    .font(TypographyTokens.headline)
                Spacer()
                Text(totalPreviewAmount)
                    .font(TypographyTokens.moneyMedium)
                    .foregroundStyle(ColorTokens.primaryOrange)
            }
        }
        .padding(.vertical, SpacingTokens.xxs)
    }

    private var taxPreviewAmount: String {
        let tax = 1000 * viewModel.defaultTaxRate / 100
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: tax)) ?? "$0.00"
    }

    private var totalPreviewAmount: String {
        let total = 1000 + (1000 * viewModel.defaultTaxRate / 100)
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: total)) ?? "$0.00"
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        TaxSettingsView(viewModel: SettingsViewModel())
    }
}
