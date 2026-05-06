import SwiftUI

/// First onboarding screen — hero mark, product name, value prop headline.
/// Stateless view; the parent flow owns transitions and completion.
struct OnboardingWelcomePage: View {
    let onPrimary: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: SpacingTokens.xl) {
            Spacer(minLength: SpacingTokens.xxl)

            // Hero mark — the real app icon, masked into iOS's continuous
            // squircle. Using the actual `app-mark` asset (sourced from
            // AppIcon) keeps onboarding aligned with what the user sees
            // on their Home Screen and the App Store, instead of a
            // synthetic SF-Symbol mash-up. The asset auto-switches to
            // the dark variant in dark mode.
            Image("app-mark")
                .resizable()
                .scaledToFit()
                .frame(width: 140, height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 18, x: 0, y: 10)
                .accessibilityHidden(true)
                .padding(.bottom, SpacingTokens.md)

            VStack(spacing: SpacingTokens.sm) {
                Text("Welcome to ProEstimate AI")
                    .font(TypographyTokens.largeTitle)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(ColorTokens.onDarkPrimary)

                Text("Turn site photos into branded estimates in minutes.")
                    .font(TypographyTokens.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(ColorTokens.onDarkSecondary)
                    .padding(.horizontal, SpacingTokens.md)
            }

            Spacer()

            VStack(spacing: SpacingTokens.sm) {
                PrimaryCTAButton(title: "Get Started", action: onPrimary)

                Button(action: onSkip) {
                    Text("Skip")
                        .font(TypographyTokens.subheadline)
                        .foregroundStyle(ColorTokens.onDarkSecondary)
                        .padding(.vertical, SpacingTokens.xs)
                }
                .accessibilityLabel("Skip onboarding")
            }
            // Lifted 16pt off the bottom edge so the CTA stack reads as
            // grounded above the page-indicator dots instead of crowding
            // them on standard iPhone heights.
            .padding(.bottom, SpacingTokens.huge)
        }
        .padding(.horizontal, SpacingTokens.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        OnboardingWelcomePage(onPrimary: {}, onSkip: {})
    }
}
