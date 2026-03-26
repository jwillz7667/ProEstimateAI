import SwiftUI

/// Card displaying a single AI-suggested material.
/// Shows name, category, estimated cost, quantity + unit, and supplier.
/// Includes a checkbox for selection, tappable supplier link, and context menu actions.
struct MaterialSuggestionCard: View {
    let material: MaterialSuggestion
    let isSelected: Bool
    let onToggle: () -> Void
    var onRemove: (() -> Void)?

    @Environment(\.openURL) private var openURL

    var body: some View {
        GlassCard {
            HStack(spacing: SpacingTokens.sm) {
                // Selection checkbox
                Button(action: onToggle) {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .font(.title3)
                        .foregroundStyle(isSelected ? ColorTokens.primaryOrange : .secondary)
                }
                .buttonStyle(.plain)

                // Material info
                VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                    Text(material.name)
                        .font(TypographyTokens.headline)
                        .lineLimit(1)

                    HStack(spacing: SpacingTokens.xs) {
                        categoryBadge

                        if let supplierName = material.supplierName {
                            if let supplierURL = material.supplierURL {
                                Button {
                                    openURL(supplierURL)
                                } label: {
                                    HStack(spacing: 2) {
                                        Text(supplierName)
                                            .font(TypographyTokens.caption)
                                        Image(systemName: "arrow.up.right.square")
                                            .font(.caption2)
                                    }
                                    .foregroundStyle(ColorTokens.primaryOrange)
                                }
                                .buttonStyle(.plain)
                            } else {
                                Text(supplierName)
                                    .font(TypographyTokens.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    HStack(spacing: SpacingTokens.sm) {
                        // Quantity + unit
                        Text("\(material.quantity) \(material.unit)")
                            .font(TypographyTokens.caption)
                            .foregroundStyle(.secondary)

                        Text("@")
                            .font(TypographyTokens.caption)
                            .foregroundStyle(.tertiary)

                        // Unit cost
                        CurrencyText(amount: material.estimatedCost, font: TypographyTokens.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Line total
                VStack(alignment: .trailing, spacing: SpacingTokens.xxs) {
                    CurrencyText(amount: material.lineTotal, font: TypographyTokens.moneySmall)

                    if material.supplierURL != nil {
                        Text("View Source")
                            .font(.caption2)
                            .foregroundStyle(ColorTokens.primaryOrange)
                    }
                }
            }
        }
        .contextMenu {
            if let onRemove {
                Button(role: .destructive, action: onRemove) {
                    Label("Remove", systemImage: "trash")
                }
            }

            if let supplierURL = material.supplierURL {
                Button {
                    openURL(supplierURL)
                } label: {
                    Label("View at \(material.supplierName ?? "Supplier")", systemImage: "safari")
                }
            }
        }
    }

    // MARK: - Subviews

    private var categoryBadge: some View {
        Text(material.category)
            .font(TypographyTokens.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, SpacingTokens.xxs)
            .padding(.vertical, 2)
            .background(
                ColorTokens.primaryOrange.opacity(0.1),
                in: Capsule()
            )
            .foregroundStyle(ColorTokens.primaryOrange)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: SpacingTokens.sm) {
        MaterialSuggestionCard(
            material: .sample,
            isSelected: true,
            onToggle: {}
        )

        MaterialSuggestionCard(
            material: MaterialSuggestion(
                id: "ms-002",
                generationId: "gen-001",
                projectId: "p-001",
                name: "Subway Tile Backsplash – White 3x6",
                category: "Tile",
                estimatedCost: 8,
                unit: "sq ft",
                quantity: 30,
                supplierName: "Floor & Decor",
                supplierURL: nil,
                isSelected: false,
                sortOrder: 1
            ),
            isSelected: false,
            onToggle: {}
        )
    }
    .padding()
}
