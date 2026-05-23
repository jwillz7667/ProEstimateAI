import SwiftUI

/// "Identified Materials" card from the overhaul screenshots — soft white
/// card with a category-tinted swatch, name + spec subtitle, and an
/// orange-highlighted estimated cost range. Selection is handled via a
/// small checkmark in the corner so the card itself reads as content.
struct MaterialSuggestionCard: View {
    let material: MaterialSuggestion
    let isSelected: Bool
    let onToggle: () -> Void
    var onRemove: (() -> Void)?

    @Environment(\.openURL) private var openURL

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: SpacingTokens.md) {
                swatch

                VStack(alignment: .leading, spacing: 2) {
                    Text(material.name)
                        .font(TypographyTokens.cardTitle)
                        .foregroundStyle(ColorTokens.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(specSubtitle)
                        .font(TypographyTokens.caption)
                        .foregroundStyle(ColorTokens.textSecondary)
                        .lineLimit(1)

                    HStack(spacing: SpacingTokens.xs) {
                        Text("EST. COST")
                            .font(.caption2.weight(.bold))
                            .tracking(0.6)
                            .foregroundStyle(ColorTokens.textTertiary)
                        Text(priceRangeLabel)
                            .font(TypographyTokens.moneyCaption.weight(.bold))
                            .foregroundStyle(ColorTokens.primaryOrange)
                    }
                    .padding(.top, 2)
                }

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(ColorTokens.primaryOrange)
                }
            }
            .padding(SpacingTokens.md)
            .glassCard()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(material.name), \(priceRangeLabel)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .contextMenu { contextMenuItems }
    }

    // MARK: - Swatch

    /// Soft tinted square containing a category-derived SF Symbol.
    /// Used in lieu of a real product image (the AI doesn't return one).
    private var swatch: some View {
        ZStack {
            RoundedRectangle(cornerRadius: RadiusTokens.small + 2)
                .fill(swatchTint)
                .frame(width: 64, height: 64)
            Image(systemName: iconForCategory(material.category))
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(ColorTokens.textPrimary.opacity(0.7))
        }
    }

    private var swatchTint: Color {
        switch material.category.lowercased() {
        case let cat where cat.contains("flooring") || cat.contains("tile"):
            ColorTokens.accentSoft
        case let cat where cat.contains("counter") || cat.contains("stone"):
            ColorTokens.pillBackground
        case let cat where cat.contains("cabinet") || cat.contains("wood"):
            Color(hex: 0xF6E7D7)
        case let cat where cat.contains("light") || cat.contains("fixture"):
            Color(hex: 0xE8E0F4)
        case let cat where cat.contains("paint") || cat.contains("wall"):
            Color(hex: 0xE6F2F0)
        default:
            ColorTokens.background
        }
    }

    private func iconForCategory(_ category: String) -> String {
        switch category.lowercased() {
        case let cat where cat.contains("flooring") || cat.contains("tile"):
            "square.grid.4x3.fill"
        case let cat where cat.contains("counter") || cat.contains("stone"):
            "rectangle.bottomthird.inset.filled"
        case let cat where cat.contains("cabinet"):
            "rectangle.stack"
        case let cat where cat.contains("light"):
            "lightbulb"
        case let cat where cat.contains("paint") || cat.contains("wall"):
            "paintpalette"
        case let cat where cat.contains("fixture") || cat.contains("plumb"):
            "drop.fill"
        default:
            "shippingbox.fill"
        }
    }

    // MARK: - Subtitle / Price

    /// "Polished Finish, Eased Edge" style subtitle, derived from the
    /// AI-supplied category + supplier when nothing better exists.
    private var specSubtitle: String {
        if let supplier = material.supplierName, !supplier.isEmpty {
            return "\(material.category) · \(supplier)"
        }
        return material.category
    }

    /// Build a friendly price range from the AI-supplied unit cost. We
    /// widen ±15% to match the screenshot's "$8 – $12 / sqft" treatment
    /// and round the bounds to clean dollar figures so the card doesn't
    /// look spuriously precise.
    private var priceRangeLabel: String {
        let unit = material.unit.isEmpty ? "ea" : material.unit
        let value = NSDecimalNumber(decimal: material.estimatedCost).doubleValue
        guard value > 0 else {
            return "—"
        }
        let low = roundedPrice(value * 0.85)
        let high = roundedPrice(value * 1.15)
        return "$\(low) – $\(high) / \(unit)"
    }

    private func roundedPrice(_ value: Double) -> String {
        if value >= 100 {
            let rounded = (value / 10).rounded() * 10
            return String(format: "%.0f", rounded)
        }
        return String(format: "%.0f", value.rounded())
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var contextMenuItems: some View {
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

        if let query = material.supplierSearchQuery, !query.isEmpty {
            ForEach(MaterialSupplier.allCases) { supplier in
                if let url = supplier.searchURL(for: query) {
                    Button {
                        openURL(url)
                    } label: {
                        Label("Verify at \(supplier.displayName)", systemImage: "magnifyingglass")
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: SpacingTokens.sm) {
        MaterialSuggestionCard(material: .sample, isSelected: true, onToggle: {})

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
    .background(ColorTokens.background)
}
