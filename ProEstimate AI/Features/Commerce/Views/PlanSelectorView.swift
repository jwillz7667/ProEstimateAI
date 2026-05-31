import SwiftUI

/// Period subscription picker for the single Pro tier.
///
/// A Monthly / Annual segmented control drives the selection; the view
/// picks the matching product from `products` and the host view model's
/// `selectedTier` / `isAnnualSelected` bindings re-resolve
/// `selectedProduct`. Pro Monthly is the default since that's where the
/// 7-day trial lives.
struct PlanSelectorView: View {
    let products: [StoreProductModel]
    let selectedProduct: StoreProductModel?
    @Binding var selectedTier: PlanTier
    @Binding var isAnnualSelected: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: SpacingTokens.md) {
            periodToggle
            currentProductCard
        }
    }

    // MARK: - Period toggle (Monthly vs Annual)

    private var periodToggle: some View {
        HStack(spacing: 0) {
            // Let the binding's didSet observer in the host VM re-resolve
            // `selectedProduct` so we can't override the user's period
            // choice on fallback.
            periodButton(title: "Monthly", isSelected: !isAnnualSelected) {
                isAnnualSelected = false
            }
            periodButton(title: "Annual", isSelected: isAnnualSelected, badge: annualSavingsBadge) {
                isAnnualSelected = true
            }
        }
        .background(Color(.tertiarySystemFill), in: Capsule())
    }

    /// Annual savings badge string, e.g. "Save 17%". Pulled from the
    /// matching annual product so we never hard-code a percentage.
    private var annualSavingsBadge: String? {
        let candidate = products.first { $0.tier == selectedTier && $0.isAnnual }
        return candidate?.savingsText
    }

    private func periodButton(
        title: String,
        isSelected: Bool,
        badge: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        // Selected state is unconditionally orange-filled; the black border
        // + black text treatment is gated only on light mode.
        let isOrangeFilled = isSelected
        return Button(action: action) {
            HStack(spacing: SpacingTokens.xxs) {
                Text(title)
                    .font(TypographyTokens.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(
                        isSelected
                            ? (colorScheme == .light ? Color.black : Color.white)
                            : ColorTokens.secondaryText
                    )
                if let badge {
                    Text(badge)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(ColorTokens.success, in: Capsule())
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, SpacingTokens.xs)
            .background(
                isSelected
                    ? Capsule().fill(ColorTokens.primaryOrange)
                    : Capsule().fill(Color.clear)
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        (isOrangeFilled && colorScheme == .light) ? Color.black : Color.clear,
                        lineWidth: (isOrangeFilled && colorScheme == .light) ? 2 : 0
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Selected product card

    @ViewBuilder
    private var currentProductCard: some View {
        if let product = currentProduct {
            VStack(alignment: .leading, spacing: SpacingTokens.xs) {
                HStack(spacing: SpacingTokens.xxs) {
                    Text(product.displayName)
                        .font(TypographyTokens.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                    Spacer()
                    if product.showsTrialBadge {
                        trialBadge
                    } else if let savings = product.savingsText, product.isAnnual {
                        savingsBadge(savings)
                    }
                }

                Text(product.priceDisplay)
                    .font(TypographyTokens.title2)
                    .foregroundStyle(.white)

                Text(product.billingPeriodLabel)
                    .font(TypographyTokens.caption)
                    .foregroundStyle(ColorTokens.onDarkTertiary)

                if let intro = product.introOfferDisplayText, product.showsTrialBadge {
                    Text(intro)
                        .font(TypographyTokens.caption)
                        .foregroundStyle(ColorTokens.primaryOrange)
                }

                Text(product.description)
                    .font(TypographyTokens.caption)
                    .foregroundStyle(ColorTokens.onDarkSecondary)
                    .padding(.top, SpacingTokens.xxs)
            }
            .padding(SpacingTokens.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Always-dark slate fill so the white-tinted copy inside
            // stays readable. `Surface` itself is now adaptive (light
            // gray in light mode), so the always-dark variant is required
            // for paywall surfaces.
            .background(
                RoundedRectangle(cornerRadius: RadiusTokens.card)
                    .fill(ColorTokens.glassCardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: RadiusTokens.card)
                    .strokeBorder(ColorTokens.primaryOrange, lineWidth: 2)
            )
        } else {
            // Empty placeholder while products load.
            RoundedRectangle(cornerRadius: RadiusTokens.card)
                .fill(ColorTokens.glassCardFill)
                .frame(height: 130)
                .overlay {
                    ProgressView().tint(.white)
                }
        }
    }

    /// Resolve the product matching the current (tier, period) selection.
    /// Falls back to the existing `selectedProduct` when no match found
    /// (e.g. StoreKit hasn't resolved the catalog yet) so the rendered
    /// card shows *something* while the host VM continues holding the
    /// user's stated period preference.
    private var currentProduct: StoreProductModel? {
        let match = products.first { $0.tier == selectedTier && $0.isAnnual == isAnnualSelected }
        return match ?? selectedProduct
    }

    // MARK: - Badges

    private var trialBadge: some View {
        Text("FREE TRIAL")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(ColorTokens.success, in: Capsule())
    }

    private func savingsBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(ColorTokens.primaryOrange, in: Capsule())
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        ColorTokens.overlayBackground.ignoresSafeArea()
        PlanSelectorView(
            products: StoreProductModel.sampleAll,
            selectedProduct: .sampleAnnual,
            selectedTier: .constant(.pro),
            isAnnualSelected: .constant(true)
        )
        .padding()
    }
}
