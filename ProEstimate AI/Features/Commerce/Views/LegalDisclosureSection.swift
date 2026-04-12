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

    /// URLs for legal pages. Update these with production URLs.
    private let termsURL = URL(string: "https://proestimate.ai/terms")!
    private let privacyURL = URL(string: "https://proestimate.ai/privacy")!

    var body: some View {
        VStack(spacing: SpacingTokens.xs) {
            // Auto-renewal disclosure.
            if let product = selectedProduct {
                autoRenewalDisclosure(product)
            }

            // Cancellation instructions.
            cancellationText

            // Legal links.
            legalLinks
        }
        .padding(.top, SpacingTokens.xs)
    }

    // MARK: - Auto-Renewal Disclosure

    private func autoRenewalDisclosure(_ product: StoreProductModel) -> some View {
        Group {
            if product.showsTrialBadge, let introText = product.introOfferDisplayText {
                Text("After the \(introText), your subscription will automatically renew at \(product.priceDisplay) \(product.billingPeriodLabel) unless cancelled at least 24 hours before the end of the current period.")
            } else {
                Text("Your subscription will automatically renew at \(product.priceDisplay) \(product.billingPeriodLabel) unless cancelled at least 24 hours before the end of the current period.")
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(.white.opacity(0.5))
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Cancellation

    private var cancellationText: some View {
        Text("You can manage or cancel your subscription at any time in your Apple ID account settings (Settings > Apple ID > Subscriptions).")
            .font(.system(size: 10))
            .foregroundStyle(.white.opacity(0.5))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Legal Links

    private var legalLinks: some View {
        HStack(spacing: SpacingTokens.md) {
            Link("Terms of Service", destination: termsURL)
            Text("|")
                .foregroundStyle(.white.opacity(0.3))
            Link("Privacy Policy", destination: privacyURL)
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(.white.opacity(0.55))
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        LegalDisclosureSection(selectedProduct: .sampleMonthly)
            .padding()
    }
}
