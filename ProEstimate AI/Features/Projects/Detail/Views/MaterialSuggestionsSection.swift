import SwiftUI

/// Displays AI-suggested materials for a project.
/// Each material has a selection checkbox; a summary shows the
/// total cost of selected materials and an "Add to Estimate" CTA.
struct MaterialSuggestionsSection: View {
    let materials: [MaterialSuggestion]
    let selectionState: [String: Bool]
    let selectedCount: Int
    let selectedTotal: Decimal
    let onToggle: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xs) {
            SectionHeaderView(
                title: "Materials",
                actionTitle: materials.isEmpty ? nil : "\(materials.count) suggested"
            )

            if materials.isEmpty {
                emptyView
            } else {
                materialsList
                selectionSummary
            }
        }
    }

    // MARK: - Subviews

    private var materialsList: some View {
        VStack(spacing: SpacingTokens.xs) {
            ForEach(materials) { material in
                MaterialSuggestionCard(
                    material: material,
                    isSelected: selectionState[material.id] ?? material.isSelected,
                    onToggle: { onToggle(material.id) }
                )
            }
        }
        .padding(.horizontal, SpacingTokens.md)
    }

    private var selectionSummary: some View {
        GlassCard {
            VStack(spacing: SpacingTokens.sm) {
                HStack {
                    Text("\(selectedCount) material\(selectedCount == 1 ? "" : "s") selected")
                        .font(TypographyTokens.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()

                    CurrencyText(amount: selectedTotal, font: TypographyTokens.moneyMedium)
                }

                if selectedCount > 0 {
                    PrimaryCTAButton(
                        title: "Add to Estimate",
                        icon: "doc.text.fill"
                    ) {
                        // Navigate to estimate creation (future phase)
                    }
                }
            }
        }
        .padding(.horizontal, SpacingTokens.md)
    }

    private var emptyView: some View {
        VStack(spacing: SpacingTokens.sm) {
            Image(systemName: "shippingbox")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No material suggestions yet")
                .font(TypographyTokens.subheadline)
                .foregroundStyle(.secondary)
            Text("Generate an AI preview to get material recommendations.")
                .font(TypographyTokens.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(SpacingTokens.xl)
        .padding(.horizontal, SpacingTokens.md)
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        MaterialSuggestionsSection(
            materials: MockGenerationService.sampleMaterials,
            selectionState: [
                "ms-001": true,
                "ms-002": true,
                "ms-003": false,
                "ms-004": true,
                "ms-005": false,
            ],
            selectedCount: 3,
            selectedTotal: 7142,
            onToggle: { _ in }
        )
    }
}
