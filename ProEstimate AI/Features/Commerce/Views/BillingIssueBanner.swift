import SwiftUI

/// Banner surfaced when the user's subscription is in a grace period or
/// billing-retry state. Non-blocking — Pro access is still active — but
/// prompts the user to fix their payment method before access is revoked.
///
/// Required by the commerce spec (monitization-spec.md §Subscription states)
/// so users aren't caught by surprise when access lapses.
struct BillingIssueBanner: View {
    @Environment(EntitlementStore.self) private var entitlementStore

    var body: some View {
        if entitlementStore.hasBillingIssue {
            content
        }
    }

    private var content: some View {
        HStack(alignment: .top, spacing: SpacingTokens.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(ColorTokens.warning)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                Text(headline)
                    .font(TypographyTokens.subheadline.weight(.semibold))
                    .foregroundStyle(ColorTokens.primaryText)

                Text(subheadline)
                    .font(TypographyTokens.caption)
                    .foregroundStyle(ColorTokens.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: SpacingTokens.sm)

            Link(destination: AppConstants.manageSubscriptionsURL) {
                Text("Update")
                    .font(TypographyTokens.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, SpacingTokens.md)
                    .padding(.vertical, SpacingTokens.xs)
                    .background(ColorTokens.warning, in: Capsule())
            }
            .accessibilityLabel("Update payment method")
            .accessibilityHint("Opens your Apple ID subscription settings")
        }
        .padding(SpacingTokens.md)
        .background(
            RoundedRectangle(cornerRadius: RadiusTokens.card)
                .fill(ColorTokens.warning.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: RadiusTokens.card)
                        .stroke(ColorTokens.warning.opacity(0.35), lineWidth: 1)
                )
        )
    }

    private var headline: String {
        switch entitlementStore.subscriptionState {
        case .gracePeriod:
            return "Subscription on hold"
        case .billingRetry:
            return "Payment issue — action needed"
        default:
            return "Billing issue"
        }
    }

    private var subheadline: String {
        if let warning = entitlementStore.billingWarning, !warning.isEmpty {
            return warning
        }
        switch entitlementStore.subscriptionState {
        case .gracePeriod:
            return "Pro access continues temporarily. Update your payment method to keep things running."
        case .billingRetry:
            return "We couldn't renew your subscription. Update your payment method to restore Pro access."
        default:
            return "Please review your Apple ID subscription settings."
        }
    }
}

// MARK: - Preview

#Preview("Grace Period") {
    BillingIssueBanner()
        .environment(EntitlementStore.preview(snapshot: .sampleGracePeriod))
        .padding()
}
