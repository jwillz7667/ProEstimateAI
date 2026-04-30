import SwiftUI

/// Three-column comparison: Free vs Pro vs Premium.
///
/// Free is everything blocked. Pro carries the monthly caps (2 projects /
/// 20 image gens / 20 estimates). Premium lifts every cap and adds
/// priority generation. Each row pulls its values from a single
/// `ComparisonFeature` so the table stays tidy and editing copy is a
/// one-line change.
struct FeatureComparisonListView: View {
    var body: some View {
        VStack(spacing: 0) {
            headerRow

            Divider()
                .background(ColorTokens.onDarkSeparator)

            ForEach(features) { feature in
                featureRow(feature)
                if feature.id != features.last?.id {
                    Divider().background(ColorTokens.onDarkFillSubtle)
                }
            }
        }
        // Use the canonical adaptive card surface so the comparison panel
        // sits on dark slate in light mode and existing dark gray in dark
        // mode. The white-tinted column copy inside stays readable on
        // either rendering.
        .background(
            ColorTokens.surface,
            in: RoundedRectangle(cornerRadius: RadiusTokens.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: RadiusTokens.card)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 0) {
            Text("Features")
                .font(TypographyTokens.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(ColorTokens.onDarkSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("Free")
                .font(TypographyTokens.caption)
                .fontWeight(.semibold)
                .foregroundStyle(ColorTokens.onDarkTertiary)
                .frame(width: tierColumnWidth)

            Text("Pro")
                .font(TypographyTokens.caption)
                .fontWeight(.bold)
                // White on dark slate (the surface stays slate in both
                // color schemes) — accentBlue text was nearly the same
                // value as the slate surface and washed out in light
                // mode. Premium keeps its orange identity for tier
                // distinction; Pro reads as the neutral white anchor.
                .foregroundStyle(.white)
                .frame(width: tierColumnWidth)

            VStack(spacing: 1) {
                Text("Premium")
                    .font(TypographyTokens.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(ColorTokens.primaryOrange)
                Image(systemName: "crown.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(ColorTokens.primaryOrange)
            }
            .frame(width: tierColumnWidth)
        }
        .padding(.horizontal, SpacingTokens.md)
        .padding(.vertical, SpacingTokens.sm)
    }

    // MARK: - Feature Row

    private func featureRow(_ feature: ComparisonFeature) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: SpacingTokens.xs) {
                Image(systemName: feature.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(ColorTokens.primaryOrange.opacity(0.7))
                    .frame(width: 20)
                Text(feature.name)
                    .font(TypographyTokens.footnote)
                    .foregroundStyle(ColorTokens.onDarkPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            valueCell(feature.freeValue, tier: .free)
                .frame(width: tierColumnWidth)
            valueCell(feature.proValue, tier: .pro)
                .frame(width: tierColumnWidth)
            valueCell(feature.premiumValue, tier: .premium)
                .frame(width: tierColumnWidth)
        }
        .padding(.horizontal, SpacingTokens.md)
        .padding(.vertical, SpacingTokens.xs)
    }

    private let tierColumnWidth: CGFloat = 60

    // MARK: - Value cell

    @ViewBuilder
    private func valueCell(_ value: FeatureValue, tier: PlanTier) -> some View {
        switch value {
        case .check:
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(checkColor(for: tier))
                .accessibilityLabel("Included")
        case .cross:
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(ColorTokens.error.opacity(tier == .free ? 0.5 : 0.7))
                .accessibilityLabel("Not included")
        case let .limited(text):
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ColorTokens.onDarkSecondary)
                .multilineTextAlignment(.center)
        case .unlimited:
            Image(systemName: "infinity")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(checkColor(for: tier))
                .accessibilityLabel("Unlimited")
        }
    }

    private func checkColor(for tier: PlanTier) -> Color {
        switch tier {
        case .free: ColorTokens.success.opacity(0.6)
        // White for Pro check / infinity glyphs — same reason as the
        // header text: blue on slate surface fades into the
        // background, especially in light mode. Premium stays orange
        // so the headline tier is visually unmistakable.
        case .pro: .white
        case .premium: ColorTokens.primaryOrange
        }
    }

    // MARK: - Feature Data

    private var features: [ComparisonFeature] {
        [
            ComparisonFeature(
                name: "Projects",
                icon: "folder",
                freeValue: .cross,
                proValue: .limited("2/mo"),
                premiumValue: .unlimited
            ),
            ComparisonFeature(
                name: "AI Image Previews",
                icon: "sparkles",
                freeValue: .cross,
                proValue: .limited("20/mo"),
                premiumValue: .unlimited
            ),
            ComparisonFeature(
                name: "AI Estimates",
                icon: "doc.text.magnifyingglass",
                freeValue: .cross,
                proValue: .limited("20/mo"),
                premiumValue: .unlimited
            ),
            ComparisonFeature(
                name: "Branded PDFs",
                icon: "doc.text",
                freeValue: .cross,
                proValue: .check,
                premiumValue: .check
            ),
            ComparisonFeature(
                name: "Custom Branding",
                icon: "paintbrush",
                freeValue: .cross,
                proValue: .check,
                premiumValue: .check
            ),
            ComparisonFeature(
                name: "Invoicing",
                icon: "dollarsign.circle",
                freeValue: .cross,
                proValue: .check,
                premiumValue: .check
            ),
            ComparisonFeature(
                name: "Client Approvals",
                icon: "checkmark.seal",
                freeValue: .cross,
                proValue: .check,
                premiumValue: .check
            ),
            ComparisonFeature(
                name: "Lawn / Roof Scout",
                icon: "scope",
                freeValue: .cross,
                proValue: .check,
                premiumValue: .check
            ),
            ComparisonFeature(
                name: "Watermark-Free",
                icon: "eye.slash",
                freeValue: .cross,
                proValue: .check,
                premiumValue: .check
            ),
            ComparisonFeature(
                name: "Priority Generation",
                icon: "bolt.fill",
                freeValue: .cross,
                proValue: .cross,
                premiumValue: .check
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
    let premiumValue: FeatureValue

    var id: String {
        name
    }
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
        ColorTokens.overlayBackground.ignoresSafeArea()
        FeatureComparisonListView()
            .padding()
    }
}
