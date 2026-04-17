import SwiftUI

/// Fourth onboarding screen — subscription trial offer. Shown as the last
/// onboarding step so the user lands on a clear value exchange:
/// "Try Pro Free for 7 Days" or continue with the free starter plan.
///
/// Tapping "Start Free Trial" presents the full `PaywallHostView` via the
/// flow's `onStartTrial` callback, where StoreKit handles the actual purchase.
/// Tapping "Continue with Free Plan" calls `onContinueFree` to complete
/// onboarding and land the user on the main app with free-tier credits.
struct OnboardingOfferPage: View {
    let onStartTrial: () -> Void
    let onContinueFree: () -> Void

    private let proBenefits: [ProBenefit] = [
        ProBenefit(icon: "infinity", title: "Unlimited AI previews", subtitle: "No more 3-a-month cap"),
        ProBenefit(icon: "doc.richtext.fill", title: "Branded PDFs", subtitle: "Your logo, colors, no watermark"),
        ProBenefit(icon: "dollarsign.circle.fill", title: "Invoicing", subtitle: "Send and track payments"),
        ProBenefit(icon: "link", title: "Client approval links", subtitle: "One-tap online sign-off"),
    ]

    var body: some View {
        VStack(spacing: SpacingTokens.xl) {
            Spacer(minLength: SpacingTokens.xl)

            header

            benefitsList

            Spacer()

            ctaStack
                .padding(.bottom, SpacingTokens.xxl)
        }
        .padding(.horizontal, SpacingTokens.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: SpacingTokens.md) {
            // Gilded "crown" hero badge.
            ZStack {
                Circle()
                    .fill(ColorTokens.primaryOrange.opacity(0.22))
                    .frame(width: 180, height: 180)
                    .blur(radius: 28)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                ColorTokens.primaryOrange,
                                ColorTokens.primaryOrange.opacity(0.82),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 104, height: 104)
                    .shadow(color: ColorTokens.primaryOrange.opacity(0.55), radius: 24, x: 0, y: 12)

                Image(systemName: "crown.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 52, height: 52)
                    .foregroundStyle(.white)
                    .accessibilityHidden(true)
            }

            VStack(spacing: SpacingTokens.xxs) {
                Text("Try Pro Free for 7 Days")
                    .font(TypographyTokens.largeTitle)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(ColorTokens.onDarkPrimary)

                Text("No commitment. Cancel anytime before the trial ends and you won't be charged.")
                    .font(TypographyTokens.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(ColorTokens.onDarkSecondary)
                    .padding(.horizontal, SpacingTokens.md)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Benefits

    private var benefitsList: some View {
        VStack(spacing: SpacingTokens.sm) {
            ForEach(proBenefits) { benefit in
                ProBenefitRow(benefit: benefit)
            }
        }
    }

    // MARK: - CTA Stack

    private var ctaStack: some View {
        VStack(spacing: SpacingTokens.sm) {
            PrimaryCTAButton(
                title: "Start 7-Day Free Trial",
                icon: "crown.fill",
                action: onStartTrial
            )

            Button(action: onContinueFree) {
                Text("Continue with Free Plan")
                    .font(TypographyTokens.subheadline)
                    .foregroundStyle(ColorTokens.onDarkSecondary)
                    .padding(.vertical, SpacingTokens.xs)
            }
            .accessibilityHint("Skip the trial and use the free starter plan")
        }
    }
}

// MARK: - Row

private struct ProBenefit: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let subtitle: String
}

private struct ProBenefitRow: View {
    let benefit: ProBenefit

    var body: some View {
        HStack(alignment: .center, spacing: SpacingTokens.md) {
            ZStack {
                RoundedRectangle(cornerRadius: RadiusTokens.button, style: .continuous)
                    .fill(ColorTokens.primaryOrange.opacity(0.18))
                    .frame(width: 44, height: 44)

                Image(systemName: benefit.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(ColorTokens.primaryOrange)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(benefit.title)
                    .font(TypographyTokens.subheadline.weight(.semibold))
                    .foregroundStyle(ColorTokens.onDarkPrimary)

                Text(benefit.subtitle)
                    .font(TypographyTokens.caption)
                    .foregroundStyle(ColorTokens.onDarkSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(SpacingTokens.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: RadiusTokens.card, style: .continuous)
                .fill(ColorTokens.onDarkFillSubtle)
        )
        .overlay(
            RoundedRectangle(cornerRadius: RadiusTokens.card, style: .continuous)
                .strokeBorder(ColorTokens.onDarkSeparator, lineWidth: 1)
        )
    }
}

#Preview {
    ZStack {
        ColorTokens.overlayBackground.ignoresSafeArea()
        OnboardingOfferPage(onStartTrial: {}, onContinueFree: {})
    }
}
