import SwiftUI

/// Step 2 of the simplified creation flow. Project name is the lead;
/// advanced fields (square footage, lot size, budget, quality tier) sit
/// below as optional context the AI uses for material/labor estimates.
struct ProjectDetailsStep: View {
    @Bindable var viewModel: ProjectCreationViewModel

    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case name, squareFootage, lotSize, budgetMin, budgetMax
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SpacingTokens.lg) {
                nameSection

                advancedHeader

                squareFootageSection
                lotSizeSection
                budgetSection
                qualityTierSection
            }
            .padding(.horizontal, SpacingTokens.md)
            .padding(.vertical, SpacingTokens.sm)
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
                    .fontWeight(.semibold)
                    .tint(ColorTokens.primaryOrange)
            }
        }
    }

    // MARK: - Name

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xs) {
            HStack(spacing: SpacingTokens.xxs) {
                Image(systemName: "pencil.line")
                    .font(.caption)
                    .foregroundStyle(ColorTokens.primaryOrange)
                Text("Project name")
                    .font(TypographyTokens.headline)
                Text("Optional")
                    .font(TypographyTokens.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, SpacingTokens.xs)
                    .padding(.vertical, 1)
                    .background(ColorTokens.inputBackground, in: Capsule())
            }

            TextField(
                viewModel.generatedTitle,
                text: $viewModel.customTitle,
                axis: .vertical
            )
            .focused($focusedField, equals: .name)
            .submitLabel(.next)
            .lineLimit(1 ... 2)
            .padding(SpacingTokens.sm)
            .background(
                ColorTokens.inputBackground,
                in: RoundedRectangle(cornerRadius: RadiusTokens.small)
            )
            .overlay(
                RoundedRectangle(cornerRadius: RadiusTokens.small)
                    .strokeBorder(ColorTokens.subtleBorder, lineWidth: 1)
            )

            Text("Leave blank and we'll auto-name this from the category.")
                .font(TypographyTokens.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Advanced Header

    private var advancedHeader: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
            Divider()
                .padding(.vertical, SpacingTokens.xxs)

            Text("Advanced (optional)")
                .font(TypographyTokens.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            Text("These help the AI tailor material quantities and cost estimates. Skip them and we'll use sensible defaults.")
                .font(TypographyTokens.caption)
                .foregroundStyle(.secondary)
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

    // MARK: - Quality Tier

    private var qualityTierSection: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xs) {
            Label("Quality tier", systemImage: "star.circle")
                .font(TypographyTokens.headline)

            Text("Influences material suggestions and cost estimates.")
                .font(TypographyTokens.caption)
                .foregroundStyle(.secondary)

            Picker("Quality", selection: $viewModel.qualityTier) {
                ForEach(Project.QualityTier.allCases, id: \.self) { tier in
                    Text(tierLabel(tier)).tag(tier)
                }
            }
            .pickerStyle(.segmented)
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

    private func tierLabel(_ tier: Project.QualityTier) -> String {
        switch tier {
        case .standard: "Standard"
        case .premium: "Premium"
        case .luxury: "Luxury"
        }
    }
}

// MARK: - Preview

#Preview {
    ProjectDetailsStep(viewModel: ProjectCreationViewModel())
}
