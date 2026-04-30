import SwiftUI

/// First onboarding screen — hero mark, product name, value prop headline.
/// Stateless view; the parent flow owns transitions and completion.
struct OnboardingWelcomePage: View {
    let onPrimary: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: SpacingTokens.xl) {
            Spacer(minLength: SpacingTokens.xxl)

            // Hero mark — orange circle with a house glyph sized for prominence.
            ZStack {
                Circle()
                    .fill(ColorTokens.primaryOrange.opacity(0.18))
                    .frame(width: 200, height: 200)
                    .blur(radius: 24)

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
                    .frame(width: 140, height: 140)
                    .shadow(color: ColorTokens.primaryOrange.opacity(0.55), radius: 24, x: 0, y: 12)

                Image(systemName: "house.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                    .foregroundStyle(.white)
                    .accessibilityHidden(true)
            }
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
