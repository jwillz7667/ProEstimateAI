import SwiftUI

/// Displays AI-suggested materials for a project.
/// Each material has a selection checkbox; a summary shows the
/// total cost of selected materials and an "Add to Estimate" CTA.
/// Includes a DIY/Professional toggle that affects labor cost inclusion.
struct MaterialSuggestionsSection: View {
    let materials: [MaterialSuggestion]
    let selectionState: [String: Bool]
    let selectedCount: Int
    let selectedTotal: Decimal
    let isDIY: Bool
    let onToggle: (String) -> Void
    var onToggleDIY: (() -> Void)?
    var onAddToEstimate: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xs) {
            SectionHeaderView(
                title: "Materials",
                actionTitle: materials.isEmpty ? nil : "\(materials.count) suggested"
            )

            if materials.isEmpty {
                emptyView
            } else {
                // DIY / Professional toggle
                diyToggle

                materialsList
                selectionSummary
            }
        }
    }

    // MARK: - Subviews

    private var diyToggle: some View {
        GlassCard {
            HStack(spacing: SpacingTokens.sm) {
                Image(systemName: isDIY ? "wrench.and.screwdriver" : "person.badge.shield.checkmark")
                    .font(.title3)
                    .foregroundStyle(isDIY ? ColorTokens.primaryOrange : .blue)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(isDIY ? "DIY Project" : "Professional Job")
                        .font(TypographyTokens.headline)

                    Text(isDIY
                        ? "Materials only — no labor costs included"
                        : "Includes labor costs for professional installation")
                        .font(TypographyTokens.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { !isDIY },
                    set: { _ in onToggleDIY?() }
                ))
                .labelsHidden()
                .tint(.blue)
            }
        }
        .padding(.horizontal, SpacingTokens.md)
    }

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

                if !isDIY {
                    HStack {
                        Image(systemName: "hammer")
                            .font(.caption)
                            .foregroundStyle(.blue)
                        Text("Labor costs will be added automatically")
                            .font(TypographyTokens.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }

                if selectedCount > 0 {
                    PrimaryCTAButton(
                        title: isDIY ? "Create DIY Estimate" : "Create Professional Estimate",
                        icon: "doc.text.fill"
                    ) {
                        onAddToEstimate?()
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
            isDIY: false,
            onToggle: { _ in }
        )
    }
}
