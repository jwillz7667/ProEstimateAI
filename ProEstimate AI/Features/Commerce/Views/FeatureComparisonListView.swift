import SwiftUI

/// Two-column comparison showing Free vs Pro feature availability.
/// Uses checkmarks and crosses with clear row-by-row differentiation
/// to highlight the value of upgrading.
struct FeatureComparisonListView: View {
    var body: some View {
        VStack(spacing: 0) {
            // Header row.
            headerRow

            Divider()
                .background(.white.opacity(0.1))

            // Feature rows.
            ForEach(features) { feature in
                featureRow(feature)

                if feature.id != features.last?.id {
                    Divider()
                        .background(.white.opacity(0.05))
                }
            }
        }
        .background(.white.opacity(0.03), in: RoundedRectangle(cornerRadius: RadiusTokens.card))
        .overlay(
            RoundedRectangle(cornerRadius: RadiusTokens.card)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack {
            Text("Features")
                .font(TypographyTokens.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.white.opacity(0.5))
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("Free")
                .font(TypographyTokens.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 50)

            Text("Pro")
                .font(TypographyTokens.caption)
                .fontWeight(.bold)
                .foregroundStyle(ColorTokens.primaryOrange)
                .frame(width: 50)
        }
        .padding(.horizontal, SpacingTokens.md)
        .padding(.vertical, SpacingTokens.sm)
    }

    // MARK: - Feature Row

    private func featureRow(_ feature: ComparisonFeature) -> some View {
        HStack {
            // Feature label with icon.
            HStack(spacing: SpacingTokens.xs) {
                Image(systemName: feature.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(ColorTokens.primaryOrange.opacity(0.7))
                    .frame(width: 20)

                Text(feature.name)
                    .font(TypographyTokens.footnote)
                    .foregroundStyle(.white.opacity(0.9))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Free column.
            freeValue(feature.freeValue)
                .frame(width: 50)

            // Pro column.
            proValue(feature.proValue)
                .frame(width: 50)
        }
        .padding(.horizontal, SpacingTokens.md)
        .padding(.vertical, SpacingTokens.xs)
    }

    // MARK: - Value Cells

    @ViewBuilder
    private func freeValue(_ value: FeatureValue) -> some View {
        switch value {
        case .check:
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(ColorTokens.success.opacity(0.6))
        case .cross:
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(ColorTokens.error.opacity(0.5))
        case .limited(let text):
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
        case .unlimited:
            Image(systemName: "infinity")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(ColorTokens.success)
        }
    }

    @ViewBuilder
    private func proValue(_ value: FeatureValue) -> some View {
        switch value {
        case .check:
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(ColorTokens.success)
        case .cross:
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(ColorTokens.error)
        case .limited(let text):
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
        case .unlimited:
            Image(systemName: "infinity")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(ColorTokens.primaryOrange)
        }
    }

    // MARK: - Feature Data

    private var features: [ComparisonFeature] {
        [
            ComparisonFeature(
                name: "AI Previews",
                icon: "sparkles",
                freeValue: .limited("3"),
                proValue: .unlimited
            ),
            ComparisonFeature(
                name: "Quote Exports",
                icon: "doc.text",
                freeValue: .limited("3"),
                proValue: .unlimited
            ),
            ComparisonFeature(
                name: "Watermark-Free",
                icon: "eye.slash",
                freeValue: .cross,
                proValue: .check
            ),
            ComparisonFeature(
                name: "Custom Branding",
                icon: "paintbrush",
                freeValue: .cross,
                proValue: .check
            ),
            ComparisonFeature(
                name: "Invoicing",
                icon: "dollarsign.circle",
                freeValue: .cross,
                proValue: .check
            ),
            ComparisonFeature(
                name: "Client Approvals",
                icon: "checkmark.seal",
                freeValue: .cross,
                proValue: .check
            ),
            ComparisonFeature(
                name: "Material Links",
                icon: "link",
                freeValue: .cross,
                proValue: .check
            ),
            ComparisonFeature(
                name: "High-Res Export",
                icon: "photo",
                freeValue: .cross,
                proValue: .check
            ),
        ]
    }
}

// MARK: - Supporting Types

private struct ComparisonFeature: Identifiable {
    let name: String
    let icon: String
    let freeValue: FeatureValue
    let proValue: FeatureValue

    var id: String { name }
}

private enum FeatureValue {
    case check
    case cross
    case limited(String)
    case unlimited
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        FeatureComparisonListView()
            .padding()
    }
}
