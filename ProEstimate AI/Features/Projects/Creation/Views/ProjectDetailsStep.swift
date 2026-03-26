import SwiftUI

/// Step 4: Optional project details — budget range, quality tier,
/// square footage, and dimensions.
struct ProjectDetailsStep: View {
    @Bindable var viewModel: ProjectCreationViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SpacingTokens.lg) {
                Text("Project Details")
                    .font(TypographyTokens.title3)

                Text("These fields are optional but help the AI generate more accurate previews and cost estimates.")
                    .font(TypographyTokens.subheadline)
                    .foregroundStyle(.secondary)

                // Budget Range
                budgetSection

                // Quality Tier
                qualityTierSection

                // Square Footage
                squareFootageSection

                // Dimensions
                dimensionsSection
            }
            .padding(.horizontal, SpacingTokens.md)
            .padding(.vertical, SpacingTokens.sm)
        }
    }

    // MARK: - Sections

    private var budgetSection: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xs) {
            Label("Budget Range", systemImage: "dollarsign.circle")
                .font(TypographyTokens.headline)

            HStack(spacing: SpacingTokens.sm) {
                VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                    Text("Minimum")
                        .font(TypographyTokens.caption)
                        .foregroundStyle(.secondary)
                    currencyField(text: $viewModel.budgetMinText, placeholder: "$0")
                }

                Text("–")
                    .foregroundStyle(.secondary)
                    .padding(.top, SpacingTokens.md)

                VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                    Text("Maximum")
                        .font(TypographyTokens.caption)
                        .foregroundStyle(.secondary)
                    currencyField(text: $viewModel.budgetMaxText, placeholder: "$0")
                }
            }
        }
        .padding(SpacingTokens.md)
        .glassCard(cornerRadius: RadiusTokens.card)
    }

    private var qualityTierSection: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xs) {
            Label("Quality Tier", systemImage: "star.circle")
                .font(TypographyTokens.headline)

            Text("Affects material suggestions and cost estimates.")
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

    private var squareFootageSection: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xs) {
            Label("Square Footage", systemImage: "ruler")
                .font(TypographyTokens.headline)

            TextField("e.g. 250", text: $viewModel.squareFootageText)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
        }
        .padding(SpacingTokens.md)
        .glassCard(cornerRadius: RadiusTokens.card)
    }

    private var dimensionsSection: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xs) {
            Label("Dimensions", systemImage: "arrow.left.and.right")
                .font(TypographyTokens.headline)

            TextField("e.g. 20x12.5", text: $viewModel.dimensions)
                .textFieldStyle(.roundedBorder)

            Text("Length x Width format, in feet")
                .font(TypographyTokens.caption)
                .foregroundStyle(.secondary)
        }
        .padding(SpacingTokens.md)
        .glassCard(cornerRadius: RadiusTokens.card)
    }

    // MARK: - Helpers

    private func currencyField(text: Binding<String>, placeholder: String) -> some View {
        HStack(spacing: SpacingTokens.xxs) {
            Text("$")
                .font(TypographyTokens.body)
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .keyboardType(.decimalPad)
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
