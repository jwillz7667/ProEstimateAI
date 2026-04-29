import SwiftUI

/// Small-print legal disclosures required by App Store Review Guidelines.
/// Includes links to Terms of Service and Privacy Policy, auto-renewal
/// disclosure, and cancellation instructions.
///
/// From App Store Review Guideline 3.1.2:
/// - Clearly disclose subscription terms, pricing, and auto-renewal.
/// - Provide links to Terms of Use and Privacy Policy.
/// - Explain how to cancel.
struct LegalDisclosureSection: View {
    let selectedProduct: StoreProductModel?

    var body: some View {
        VStack(spacing: SpacingTokens.xs) {
            // Auto-renewal disclosure (App Store Review Guideline 3.1.2(a)).
            if let product = selectedProduct {
                autoRenewalDisclosure(product)
            }

            // Cancellation instructions with tappable subscription management link.
            cancellationText

            // Legal links: Terms, Privacy, Manage Subscriptions.
            legalLinks
        }
        .padding(.top, SpacingTokens.xs)
    }

    // MARK: - Auto-Renewal Disclosure

    private func autoRenewalDisclosure(_ product: StoreProductModel) -> some View {
        // App Store Review Guideline 3.1.2(a) requires:
        // (1) title/length, (2) price per period, (3) auto-renewal terms,
        // (4) "charged within 24 hours prior to end of period" language,
        // (5) cancellation method, (6) Privacy Policy + Terms links.
        Group {
            if product.showsTrialBadge, let introText = product.introOfferDisplayText {
                Text("After the \(introText), your \(product.displayName) subscription automatically renews at \(product.priceDisplay) unless canceled at least 24 hours before the end of the current period. Your Apple ID will be charged for renewal within 24 hours prior to the end of each billing period.")
            } else {
                Text("Your \(product.displayName) subscription automatically renews at \(product.priceDisplay) unless canceled at least 24 hours before the end of the current period. Your Apple ID will be charged for renewal within 24 hours prior to the end of each billing period.")
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(ColorTokens.tertiaryText)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Cancellation

    private var cancellationText: some View {
        Text("Manage or cancel anytime from your Apple ID subscription settings.")
            .font(.system(size: 10))
            .foregroundStyle(ColorTokens.tertiaryText)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Legal Links

    private var legalLinks: some View {
        VStack(spacing: SpacingTokens.xxs) {
            HStack(spacing: SpacingTokens.md) {
                Link("Terms of Service", destination: AppConstants.termsOfServiceURL)
                Text("|")
                    .foregroundStyle(ColorTokens.tertiaryText.opacity(0.6))
                Link("Privacy Policy", destination: AppConstants.privacyPolicyURL)
            }
            Link("Manage Subscriptions", destination: AppConstants.manageSubscriptionsURL)
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(ColorTokens.tertiaryText)
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        ColorTokens.overlayBackground.ignoresSafeArea()
        LegalDisclosureSection(selectedProduct: .sampleMonthly)
            .padding()
    }
}
