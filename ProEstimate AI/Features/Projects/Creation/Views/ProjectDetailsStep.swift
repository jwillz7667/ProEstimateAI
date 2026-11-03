import SwiftUI

/// Optional measurements and budget, embedded in the creation page's
/// disclosure. These fields do not add another required wizard page.
struct ProjectDetailsStep: View {
    @Bindable var viewModel: ProjectCreationViewModel

    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case squareFootage, lotSize, budgetMin, budgetMax
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.md) {
            Text(viewModel.shouldGenerateAI
                 ? "Add measurements or a budget to help tailor the estimate. You can leave these blank."
                 : "Save measurements and a budget for reference. You can add these later.")
                .font(TypographyTokens.caption)
                .foregroundStyle(.secondary)
            squareFootageSection
            lotSizeSection
            budgetSection
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                if focusedField != nil {
                    Spacer()
                    Button("Done") { focusedField = nil }
                        .fontWeight(.semibold)
                        .tint(ColorTokens.primaryOrange)
                }
            }
        }
    }

    // MARK: - Square Footage

    private var squareFootageSection: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xs) {
            Label("Project area", systemImage: "ruler")
                .font(TypographyTokens.headline)

            HStack(spacing: SpacingTokens.xs) {
                TextField("e.g. 250", text: $viewModel.squareFootageText)
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: .squareFootage)
                    .textFieldStyle(.roundedBorder)
                Text("sqft")
                    .font(TypographyTokens.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Approximate working area for this remodel.")
                .font(TypographyTokens.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(SpacingTokens.md)
        .glassCard(cornerRadius: RadiusTokens.card)
    }

    // MARK: - Lot Size

    private var lotSizeSection: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xs) {
            Label("Lot size", systemImage: "square.dashed")
                .font(TypographyTokens.headline)

            HStack(spacing: SpacingTokens.xs) {
                TextField("e.g. 5000", text: $viewModel.lotSizeText)
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: .lotSize)
                    .textFieldStyle(.roundedBorder)
                Text("sqft")
                    .font(TypographyTokens.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Total property lot size — useful for exterior, landscaping, and lawn jobs.")
                .font(TypographyTokens.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(SpacingTokens.md)
        .glassCard(cornerRadius: RadiusTokens.card)
    }

    // MARK: - Budget

    private var budgetSection: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xs) {
            Label("Budget range", systemImage: "dollarsign.circle")
                .font(TypographyTokens.headline)

            HStack(spacing: SpacingTokens.sm) {
                VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                    Text("Min")
                        .font(TypographyTokens.caption)
                        .foregroundStyle(.secondary)
                    currencyField(text: $viewModel.budgetMinText, placeholder: "0", focus: .budgetMin)
                }

                Text("–")
                    .foregroundStyle(.secondary)
                    .padding(.top, SpacingTokens.md)

                VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                    Text("Max")
                        .font(TypographyTokens.caption)
                        .foregroundStyle(.secondary)
                    currencyField(text: $viewModel.budgetMaxText, placeholder: "0", focus: .budgetMax)
                }
            }
        }
        .padding(SpacingTokens.md)
        .glassCard(cornerRadius: RadiusTokens.card)
    }

    // MARK: - Helpers

    private func currencyField(text: Binding<String>, placeholder: String, focus: Field) -> some View {
        HStack(spacing: SpacingTokens.xxs) {
            Text("$")
                .font(TypographyTokens.body)
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .keyboardType(.decimalPad)
                .focused($focusedField, equals: focus)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, SpacingTokens.sm)
        .padding(.vertical, SpacingTokens.xs)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: RadiusTokens.button))
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        ProjectDetailsStep(viewModel: ProjectCreationViewModel())
            .padding()
    }
}
