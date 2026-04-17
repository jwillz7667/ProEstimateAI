import SwiftUI

/// Toggle between Monthly and Annual subscription plans.
/// Each plan card shows: price, billing period, trial badge (if eligible),
/// and "Save X%" badge on annual. The selected plan has an orange border.
struct PlanSelectorView: View {
    let products: [StoreProductModel]
    let selectedProduct: StoreProductModel?
    @Binding var isAnnualSelected: Bool
    let onSelect: (StoreProductModel) -> Void

    var body: some View {
        VStack(spacing: SpacingTokens.sm) {
            // Period toggle.
            periodToggle

            // Plan cards.
            HStack(spacing: SpacingTokens.sm) {
                if let monthly = products.first(where: { $0.isMonthly }) {
                    planCard(product: monthly)
                }
                if let annual = products.first(where: { $0.isAnnual }) {
                    planCard(product: annual)
                }
            }
        }
    }

    // MARK: - Period Toggle

    private var periodToggle: some View {
        HStack(spacing: 0) {
            toggleButton(title: "Monthly", isSelected: !isAnnualSelected) {
                isAnnualSelected = false
            }

            toggleButton(title: "Annual", isSelected: isAnnualSelected) {
                isAnnualSelected = true
            }
        }
        .background(ColorTokens.onDarkFillSubtle, in: Capsule())
        .padding(.horizontal, SpacingTokens.xxxl)
    }

    private func toggleButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(TypographyTokens.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? Color.white : ColorTokens.onDarkTertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, SpacingTokens.xs)
                .background(
                    isSelected
                        ? Capsule().fill(ColorTokens.primaryOrange)
                        : Capsule().fill(Color.clear)
                )
        }
    }

    // MARK: - Plan Card

    private func planCard(product: StoreProductModel) -> some View {
        let isSelected = selectedProduct?.productId == product.productId

        return Button {
            onSelect(product)
        } label: {
            VStack(alignment: .leading, spacing: SpacingTokens.xs) {
                // Plan name + badges.
                HStack(spacing: SpacingTokens.xxs) {
                    Text(product.displayName)
                        .font(TypographyTokens.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)

                    Spacer()

                    if product.showsTrialBadge {
                        trialBadge
                    }

                    if let savings = product.savingsText {
                        savingsBadge(savings)
                    }
                }

                // Price.
                Text(product.priceDisplay)
                    .font(TypographyTokens.title2)
                    .foregroundStyle(.white)

                // Billing period.
                Text(product.billingPeriodLabel)
                    .font(TypographyTokens.caption)
                    .foregroundStyle(ColorTokens.onDarkTertiary)

                // Intro offer text.
                if let introText = product.introOfferDisplayText, product.showsTrialBadge {
                    Text(introText)
                        .font(TypographyTokens.caption)
                        .foregroundStyle(ColorTokens.primaryOrange)
                }
            }
            .padding(SpacingTokens.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: RadiusTokens.card)
                    .fill(isSelected ? ColorTokens.onDarkSeparator : ColorTokens.onDarkFillSubtle)
            )
            .overlay(
                RoundedRectangle(cornerRadius: RadiusTokens.card)
                    .strokeBorder(
                        isSelected ? ColorTokens.primaryOrange : ColorTokens.onDarkSeparator,
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
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
            products: [.sampleMonthly, .sampleAnnual],
            selectedProduct: .sampleAnnual,
            isAnnualSelected: .constant(true),
            onSelect: { _ in }
        )
        .padding()
    }
}
