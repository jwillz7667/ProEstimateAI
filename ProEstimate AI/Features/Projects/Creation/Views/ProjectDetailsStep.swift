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

                // Recurring contract terms — surfaced when the project type
                // is configured as recurring by default (LAWN_CARE today)
                // OR when the contractor manually flipped on recurring.
                if showsRecurrenceConfig {
                    recurrenceSection
                }

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
        .onAppear {
            // First time we land on Details after picking lawnCare:
            // pre-flip recurrence on so the field is visible and ready
            // without making the contractor hunt for a toggle.
            if viewModel.selectedProjectType?.isRecurringByDefault == true,
               !viewModel.isRecurring
            {
                viewModel.isRecurring = true
            }
        }
    }

    private var showsRecurrenceConfig: Bool {
        // Always show for project types that are recurring-by-default; for
        // others, only show after the contractor explicitly toggles on.
        viewModel.selectedProjectType?.isRecurringByDefault == true
            || viewModel.isRecurring
    }

    // MARK: - Sections

    private var recurrenceSection: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.sm) {
            Label("Recurring Contract", systemImage: "calendar.badge.clock")
                .font(TypographyTokens.headline)

            Text("Sell this as a recurring service contract. Materials and labor below are quoted PER VISIT; the proposal will roll up monthly and annual totals.")
                .font(TypographyTokens.caption)
                .foregroundStyle(.secondary)

            Toggle("Bill as Recurring", isOn: $viewModel.isRecurring)
                .tint(ColorTokens.primaryOrange)

            if viewModel.isRecurring {
                Divider().padding(.vertical, SpacingTokens.xxs)

                // Frequency
                VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                    Text("Frequency")
                        .font(TypographyTokens.caption)
                        .foregroundStyle(.secondary)
                    Picker("Frequency", selection: $viewModel.recurrenceFrequency) {
                        ForEach(Project.RecurrenceFrequency.allCases, id: \.self) { freq in
                            Text(freq.displayName).tag(freq)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: viewModel.recurrenceFrequency) { _, newValue in
                        // Clear an explicit override when the cadence
                        // changes so the new cadence's default takes effect
                        // unless the user re-enters an override.
                        viewModel.visitsPerMonthText = ""
                        _ = newValue
                    }
                }

                // Visits per month (override)
                VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                    Text("Visits / Month")
                        .font(TypographyTokens.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: SpacingTokens.xs) {
                        TextField(
                            "Default \(defaultVisitsHint)",
                            text: $viewModel.visitsPerMonthText
                        )
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        Text("visits")
                            .font(TypographyTokens.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("Leave blank to use the cadence default.")
                        .font(TypographyTokens.caption2)
                        .foregroundStyle(.tertiary)
                }

                // Contract length
                VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                    Text("Contract Length")
                        .font(TypographyTokens.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: SpacingTokens.xs) {
                        TextField("8", text: $viewModel.contractMonthsText)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        Text("months")
                            .font(TypographyTokens.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("Typical: 8 months for cool-season turf, 12 for year-round HOA contracts.")
                        .font(TypographyTokens.caption2)
                        .foregroundStyle(.tertiary)
                }

                // Start date
                DatePicker(
                    "Start Date",
                    selection: $viewModel.recurrenceStartDate,
                    displayedComponents: .date
                )
                .font(TypographyTokens.caption)

                // Live rollup preview
                if let visits = viewModel.resolvedVisitsPerMonth,
                   let months = viewModel.contractMonths
                {
                    let totalVisits = visits * Decimal(months)
                    HStack {
                        Text("Total visits over contract")
                            .font(TypographyTokens.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(NSDecimalNumber(decimal: totalVisits).intValue)")
                            .font(TypographyTokens.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(ColorTokens.primaryOrange)
                    }
                    .padding(.top, SpacingTokens.xs)
                }
            }
        }
        .padding(SpacingTokens.md)
        .glassCard(cornerRadius: RadiusTokens.card)
    }

    /// Numeric hint shown in the visits-per-month placeholder. Tracks the
    /// selected cadence's default so the contractor sees what the bid
    /// will use when the override is left blank.
    private var defaultVisitsHint: String {
        let v = viewModel.recurrenceFrequency.defaultVisitsPerMonth
        let n = NSDecimalNumber(decimal: v).doubleValue
        // Quarterly is fractional; everything else is whole.
        return n.rounded() == n
            ? String(Int(n))
            : String(format: "%.2f", n)
    }

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
