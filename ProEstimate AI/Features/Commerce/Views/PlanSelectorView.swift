import SwiftUI

/// Three-tier vertical paywall card stack matching the overhaul
/// `upgrade_paywall.png` screenshot. Renders Free / Pro / Business cards
/// and forwards the resolved purchase target through `onSelect`.
///
/// Mapping:
/// - Free   → virtual tier (no product). Marked "Current Plan" when the
///   user has no active entitlement.
/// - Pro    → Pro Monthly product (matches PlanCode.proMonthly).
/// - Business → Premium Monthly product (matches PlanCode.premiumMonthly).
///
/// The host view model owns `selectedTier` / `isAnnualSelected` for
/// backwards compatibility; this picker writes to them so other parts of
/// the system (analytics, telemetry) keep working.
struct PlanSelectorView: View {
    let products: [StoreProductModel]
    let selectedProduct: StoreProductModel?
    @Binding var selectedTier: PlanTier
    @Binding var isAnnualSelected: Bool
    let onSelect: (StoreProductModel) -> Void

    var body: some View {
        VStack(spacing: SpacingTokens.lg) {
            tierCard(.free)
            tierCard(.pro)
            tierCard(.business)
        }
    }

    // MARK: - Internal Tier Description

    /// Local enum so we can render Free + Pro + Business with one switch.
    /// The Free row maps to no `StoreProductModel`; the other two map to
    /// Pro Monthly and Premium Monthly respectively.
    private enum TierKind: Hashable {
        case free
        case pro
        case business

        var title: String {
            switch self {
            case .free: "Free"
            case .pro: "Pro"
            case .business: "Business"
            }
        }

        var price: String {
            switch self {
            case .free: "$0"
            case .pro: "$19"
            case .business: "$49"
            }
        }

        var period: String {
            switch self {
            case .free: "/mo"
            case .pro: "/mo"
            case .business: "/mo"
            }
        }

        var blurb: String {
            switch self {
            case .free:
                "Essential tools to explore the platform."
            case .pro:
                "For independent contractors who need unconstrained visualization."
            case .business:
                "Complete suite for teams managing multiple client builds."
            }
        }

        var bullets: [String] {
            switch self {
            case .free: [
                    "1 Vision Generation / mo",
                    "Basic Project Dashboard",
                    "Material Lists",
                ]
            case .pro: [
                    "Unlimited Visions",
                    "Automated Material Lists",
                    "High-Res Exports",
                    "Priority Support",
                ]
            case .business: [
                    "Everything in Pro",
                    "Advanced Contractor Tools",
                    "Custom Branding",
                    "Client Management Portal",
                ]
            }
        }

        /// Bullets that should render greyed out (feature exists in higher
        /// tier only). Used to subtly indicate the upgrade path on the Free
        /// card without removing the row entirely.
        var dimmedBullets: Set<String> {
            switch self {
            case .free: ["Material Lists"]
            default: []
            }
        }
    }

    // MARK: - Tier Card

    @ViewBuilder
    private func tierCard(_ kind: TierKind) -> some View {
        let isMostPopular = (kind == .pro)
        let product = product(for: kind)

        VStack(spacing: 0) {
            if isMostPopular {
                Text("Most Popular")
                    .font(TypographyTokens.caption.weight(.semibold))
                    .padding(.horizontal, SpacingTokens.md)
                    .padding(.vertical, 6)
                    .background(ColorTokens.heroBackground, in: Capsule())
                    .foregroundStyle(ColorTokens.heroForeground)
                    .offset(y: 14)
                    .zIndex(1)
            }

            VStack(alignment: .leading, spacing: SpacingTokens.md) {
                tierHeader(kind: kind)
                bulletList(kind: kind)
                ctaButton(kind: kind, product: product)
            }
            .padding(SpacingTokens.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ColorTokens.surface, in: RoundedRectangle(cornerRadius: RadiusTokens.hero))
            .overlay(
                RoundedRectangle(cornerRadius: RadiusTokens.hero)
                    .strokeBorder(
                        isMostPopular ? ColorTokens.primaryOrange.opacity(0.5) : ColorTokens.cardStroke,
                        lineWidth: isMostPopular ? 2 : 1
                    )
            )
            .shadow(isMostPopular ? ShadowTokens.large : ShadowTokens.small)
        }
    }

    private func tierHeader(kind: TierKind) -> some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
            Text(kind.title)
                .font(TypographyTokens.title2)
                .foregroundStyle(ColorTokens.textPrimary)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(kind.price)
                    .font(.system(.largeTitle, design: .default, weight: .bold))
                    .foregroundStyle(ColorTokens.textPrimary)
                Text(kind.period)
                    .font(TypographyTokens.subheadline)
                    .foregroundStyle(ColorTokens.textSecondary)
            }

            Text(kind.blurb)
                .font(TypographyTokens.subheadline)
                .foregroundStyle(ColorTokens.textSecondary)
                .padding(.top, 2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func bulletList(kind: TierKind) -> some View {
        VStack(alignment: .leading, spacing: SpacingTokens.sm) {
            Divider()
                .background(ColorTokens.cardStroke)
            ForEach(kind.bullets, id: \.self) { bullet in
                bulletRow(bullet, isDimmed: kind.dimmedBullets.contains(bullet), highlight: kind == .business)
            }
        }
    }

    private func bulletRow(_ text: String, isDimmed: Bool, highlight: Bool) -> some View {
        HStack(spacing: SpacingTokens.sm) {
            Image(systemName: isDimmed ? "circle" : "checkmark.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(
                    isDimmed
                        ? ColorTokens.textTertiary
                        : (highlight ? ColorTokens.primaryOrange : ColorTokens.textPrimary)
                )

            Text(text)
                .font(TypographyTokens.subheadline)
                .foregroundStyle(isDimmed ? ColorTokens.textTertiary : ColorTokens.textPrimary)
        }
    }

    @ViewBuilder
    private func ctaButton(kind: TierKind, product: StoreProductModel?) -> some View {
        switch kind {
        case .free:
            currentPlanButton

        case .pro:
            tierCTA(
                title: ctaTitle(for: product, fallback: "Subscribe to Pro"),
                style: .dark,
                isEnabled: product != nil
            ) {
                if let product { onSelect(product) }
            }

        case .business:
            tierCTA(
                title: ctaTitle(for: product, fallback: "Subscribe to Business"),
                style: .orange,
                isEnabled: product != nil
            ) {
                if let product { onSelect(product) }
            }
        }
    }

    private var currentPlanButton: some View {
        Text("Current Plan")
            .font(TypographyTokens.buttonSecondary)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(ColorTokens.background, in: RoundedRectangle(cornerRadius: RadiusTokens.button))
            .overlay(
                RoundedRectangle(cornerRadius: RadiusTokens.button)
                    .strokeBorder(ColorTokens.cardStroke, lineWidth: 1)
            )
            .foregroundStyle(ColorTokens.textSecondary)
    }

    private func tierCTA(
        title: String,
        style: PrimaryCTAButton.Style,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        PrimaryCTAButton(
            title: title,
            isDisabled: !isEnabled,
            style: style,
            action: action
        )
    }

    // MARK: - Helpers

    /// Resolve a card's `StoreProductModel` from the loaded product list.
    private func product(for kind: TierKind) -> StoreProductModel? {
        switch kind {
        case .free:
            return nil
        case .pro:
            return products.first { $0.planCode == .proMonthly }
                ?? products.first { $0.tier == .pro && $0.isMonthly }
        case .business:
            return products.first { $0.planCode == .premiumMonthly }
                ?? products.first { $0.tier == .premium && $0.isMonthly }
        }
    }

    /// Headline for the tier CTA — uses the product's intro-offer text
    /// when a free trial is available, otherwise a plain "Subscribe" string.
    private func ctaTitle(for product: StoreProductModel?, fallback: String) -> String {
        guard let product else { return "Coming Soon" }
        if product.showsTrialBadge { return "Start 7-Day Free Trial" }
        return fallback
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        ColorTokens.background.ignoresSafeArea()
        ScrollView {
            PlanSelectorView(
                products: StoreProductModel.sampleAll,
                selectedProduct: .samplePremiumAnnual,
                selectedTier: .constant(.premium),
                isAnnualSelected: .constant(false),
                onSelect: { _ in }
            )
            .padding()
        }
    }
}
