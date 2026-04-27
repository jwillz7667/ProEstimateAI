import SwiftUI

/// Tier + period subscription picker.
///
/// Two segmented controls drive the selection:
///   1. Tier (Pro vs Premium) — the headline product family.
///   2. Period (Monthly vs Annual) — billing cadence.
///
/// The view picks the right product from `products` for whatever
/// combination is selected and forwards it through `onSelect`. Pro
/// Monthly is the default since that's where the 7-day trial lives;
/// Premium gets a "Most Popular" tag and the trailing 12-mo savings.
struct PlanSelectorView: View {
    let products: [StoreProductModel]
    let selectedProduct: StoreProductModel?
    @Binding var selectedTier: PlanTier
    @Binding var isAnnualSelected: Bool
    let onSelect: (StoreProductModel) -> Void

    var body: some View {
        VStack(spacing: SpacingTokens.md) {
            tierToggle
            periodToggle
            currentProductCard
        }
    }

    // MARK: - Tier toggle (Pro vs Premium)

    private var tierToggle: some View {
        HStack(spacing: 0) {
            tierButton(.pro)
            tierButton(.premium)
        }
        .padding(2)
        .background(ColorTokens.onDarkFillSubtle, in: Capsule())
    }

    private func tierButton(_ tier: PlanTier) -> some View {
        let isSelected = selectedTier == tier
        return Button {
            selectedTier = tier
            applySelection()
        } label: {
            HStack(spacing: SpacingTokens.xxs) {
                if tier == .premium && !isSelected {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ColorTokens.primaryOrange)
                }
                Text(tier.displayName.uppercased())
                    .font(TypographyTokens.caption.weight(.bold))
                    .tracking(0.5)
                    .foregroundStyle(isSelected ? .white : ColorTokens.onDarkSecondary)
                if tier == .premium && isSelected {
                    Text("MOST POPULAR")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.white.opacity(0.18), in: Capsule())
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, SpacingTokens.xs)
            .background(
                isSelected
                    ? Capsule().fill(tier == .premium ? ColorTokens.primaryOrange : ColorTokens.accentBlue)
                    : Capsule().fill(Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Period toggle (Monthly vs Annual)

    private var periodToggle: some View {
        HStack(spacing: 0) {
            periodButton(title: "Monthly", isSelected: !isAnnualSelected) {
                isAnnualSelected = false
                applySelection()
            }
            periodButton(title: "Annual", isSelected: isAnnualSelected, badge: annualSavingsBadge) {
                isAnnualSelected = true
                applySelection()
            }
        }
        .background(ColorTokens.onDarkFillSubtle, in: Capsule())
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
        Button(action: action) {
            HStack(spacing: SpacingTokens.xxs) {
                Text(title)
                    .font(TypographyTokens.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? .white : ColorTokens.onDarkTertiary)
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
            .background(
                RoundedRectangle(cornerRadius: RadiusTokens.card)
                    .fill(ColorTokens.onDarkSeparator)
            )
            .overlay(
                RoundedRectangle(cornerRadius: RadiusTokens.card)
                    .strokeBorder(ColorTokens.primaryOrange, lineWidth: 2)
            )
        } else {
            // Empty placeholder while products load.
            RoundedRectangle(cornerRadius: RadiusTokens.card)
                .fill(ColorTokens.onDarkFillSubtle)
                .frame(height: 130)
                .overlay {
                    ProgressView().tint(.white)
                }
        }
    }

    /// Resolve the product matching the current (tier, period) selection.
    /// Falls back to the existing `selectedProduct` when no match found
    /// (e.g. backend hasn't shipped Premium yet).
    private var currentProduct: StoreProductModel? {
        let match = products.first { $0.tier == selectedTier && $0.isAnnual == isAnnualSelected }
        return match ?? selectedProduct
    }

    /// Push the (tier, period) → product resolution back up via
    /// `onSelect` so the host view model knows which product to charge.
    private func applySelection() {
        guard let resolved = currentProduct else { return }
        onSelect(resolved)
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
            selectedProduct: .samplePremiumAnnual,
            selectedTier: .constant(.premium),
            isAnnualSelected: .constant(true),
            onSelect: { _ in }
        )
        .padding()
    }
}
