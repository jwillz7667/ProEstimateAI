import SwiftUI

/// Contains the primary purchase CTA, optional "Continue with Free" button,
/// and "Restore Purchases" link.
/// The primary button shows a loading spinner during purchase.
struct PurchaseButtonSection: View {
    let primaryTitle: String
    let isPurchasing: Bool
    let isRestoring: Bool
    let showContinueFree: Bool
    let showRestorePurchases: Bool
    let secondaryCtaTitle: String?
    let selectedProduct: StoreProductModel?
    let onPurchase: () -> Void
    let onContinueFree: () -> Void
    let onRestore: () -> Void

    var body: some View {
        VStack(spacing: SpacingTokens.sm) {
            // Primary CTA.
            purchaseButton

            // Secondary "Continue with Free" button.
            if showContinueFree {
                continueFreeButton
            }

            // Restore Purchases link.
            if showRestorePurchases {
                restoreLink
            }
        }
    }

    // MARK: - Primary Purchase Button

    private var purchaseButton: some View {
        Button(action: onPurchase) {
            HStack(spacing: SpacingTokens.xs) {
                if isPurchasing {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "crown.fill")
                    Text(primaryTitle)
                        .font(TypographyTokens.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: RadiusTokens.button)
                    .fill(
                        LinearGradient(
                            colors: [ColorTokens.primaryOrange, Color(hex: 0xEA580C)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .shadow(color: ColorTokens.primaryOrange.opacity(0.4), radius: 12, y: 4)
            )
            .foregroundStyle(.white)
        }
        .disabled(isPurchasing || selectedProduct == nil)
        .opacity(selectedProduct == nil ? 0.5 : 1.0)
    }

    // MARK: - Continue Free Button

    private var continueFreeButton: some View {
        Button(action: onContinueFree) {
            Text(secondaryCtaTitle ?? "Continue with Free Plan")
                .font(TypographyTokens.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(ColorTokens.onDarkSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, SpacingTokens.sm)
        }
    }

    // MARK: - Restore Purchases Link

    private var restoreLink: some View {
        Button(action: onRestore) {
            HStack(spacing: SpacingTokens.xxs) {
                if isRestoring {
                    ProgressView()
                        .tint(ColorTokens.onDarkQuaternary)
                        .scaleEffect(0.8)
                }
                Text("Restore Purchases")
                    .font(TypographyTokens.footnote)
                    .foregroundStyle(ColorTokens.onDarkQuaternary)
                    .underline()
            }
        }
        .disabled(isRestoring)
        .padding(.top, SpacingTokens.xxs)
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        ColorTokens.overlayBackground.ignoresSafeArea()
        PurchaseButtonSection(
            primaryTitle: "Start Free Trial",
            isPurchasing: false,
            isRestoring: false,
            showContinueFree: true,
            showRestorePurchases: true,
            secondaryCtaTitle: "Continue with Free Plan",
            selectedProduct: .sampleAnnual,
            onPurchase: {},
            onContinueFree: {},
            onRestore: {}
        )
        .padding()
    }
}
