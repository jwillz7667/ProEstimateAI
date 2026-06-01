import SwiftUI

/// Lets the contractor set the margin applied on top of raw labor cost.
/// Persists `Company.laborMarkupPercent` via debounced autosave. The backend
/// applies this percent to every labor line item when assembling estimates,
/// so a $80/hr crew cost billed at 25% markup shows the client $100/hr.
struct LaborSettingsView: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        Form {
            // Labor Markup Rate
            Section {
                VStack(alignment: .leading, spacing: SpacingTokens.xs) {
                    HStack {
                        Text("Labor Markup")
                        Spacer()
                        TextField("0", text: $viewModel.laborMarkupText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                            .onChange(of: viewModel.laborMarkupText) { _, newValue in
                                if let value = Decimal(string: newValue.trimmingCharacters(in: .whitespaces)),
                                   value >= 0, value <= 999 {
                                    viewModel.laborMarkupPercent = value
                                }
                                viewModel.scheduleSaveLabor()
                            }
                        Text("%")
                            .foregroundStyle(.secondary)
                    }

                    Slider(
                        value: Binding(
                            get: { viewModel.laborMarkupSliderValue },
                            set: {
                                viewModel.laborMarkupSliderValue = $0
                                viewModel.scheduleSaveLabor()
                            }
                        ),
                        in: 0 ... 100,
                        step: 1
                    )
                    .tint(ColorTokens.primaryOrange)
                }
            } header: {
                Text("Markup on Labor")
            } footer: {
                Text("Your margin on top of raw labor cost. Applied automatically to every labor line when an estimate is generated. Materials use a separate markup.")
            }

            // Preview
            Section("Preview") {
                laborPreview
            }
        }
        .navigationTitle("Labor Markup")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SettingsSaveStatusView(status: viewModel.saveStatus)
            }
        }
    }

    // MARK: - Preview

    /// Worked example on a representative crew cost so the contractor sees the
    /// billed rate their markup produces before any estimate is generated.
    private var laborPreview: some View {
        VStack(spacing: SpacingTokens.xs) {
            HStack {
                Text("Crew cost")
                    .font(TypographyTokens.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formatCurrency(sampleCrewCost))
                    .font(TypographyTokens.moneySmall)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Markup (\(SettingsViewModel.formatMarkup(viewModel.laborMarkupPercent))%)")
                    .font(TypographyTokens.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formatCurrency(markupAmount))
                    .font(TypographyTokens.moneySmall)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Text("Billed to client")
                    .font(TypographyTokens.headline)
                Spacer()
                Text(formatCurrency(billedAmount))
                    .font(TypographyTokens.moneyMedium)
                    .foregroundStyle(ColorTokens.primaryOrange)
            }
        }
        .padding(.vertical, SpacingTokens.xxs)
    }

    // MARK: - Preview Math

    private let sampleCrewCost: Decimal = 800

    private var markupAmount: Decimal {
        sampleCrewCost * viewModel.laborMarkupPercent / 100
    }

    private var billedAmount: Decimal {
        sampleCrewCost + markupAmount
    }

    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "$0.00"
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        LaborSettingsView(viewModel: SettingsViewModel())
    }
}
