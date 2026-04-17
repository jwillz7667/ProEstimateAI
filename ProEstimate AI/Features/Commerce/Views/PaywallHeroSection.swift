import SwiftUI

/// The top section of the paywall with a gradient background,
/// app icon area, headline, and subheadline.
/// Uses an animated entrance for visual polish.
struct PaywallHeroSection: View {
    let decision: PaywallDecision

    @State private var isVisible: Bool = false

    var body: some View {
        VStack(spacing: SpacingTokens.lg) {
            Spacer()
                .frame(height: SpacingTokens.xxxl)

            // App icon / illustration area.
            iconArea

            // Headline.
            Text(decision.headline)
                .font(TypographyTokens.title)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            // Subheadline.
            Text(decision.subheadline)
                .font(TypographyTokens.body)
                .foregroundStyle(ColorTokens.onDarkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, SpacingTokens.xl)
        .padding(.bottom, SpacingTokens.xxl)
        .frame(maxWidth: .infinity)
        .background(heroGradient)
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? 0 : 20)
        .animation(.easeOut(duration: 0.6), value: isVisible)
        .onAppear {
            isVisible = true
        }
    }

    // MARK: - Icon Area

    private var iconArea: some View {
        ZStack {
            // Glowing ring behind the icon.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            ColorTokens.primaryOrange.opacity(0.3),
                            ColorTokens.primaryOrange.opacity(0.0)
                        ],
                        center: .center,
                        startRadius: 20,
                        endRadius: 60
                    )
                )
                .frame(width: 120, height: 120)

            // Crown icon representing Pro.
            Image(systemName: "crown.fill")
                .font(.system(size: 44))
                .foregroundStyle(
                    LinearGradient(
                        colors: [ColorTokens.primaryOrange, Color(hex: 0xFBBF24)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: ColorTokens.primaryOrange.opacity(0.5), radius: 12, y: 4)
        }
    }

    // MARK: - Gradient Background

    private var heroGradient: some View {
        LinearGradient(
            colors: [
                ColorTokens.overlayAccent,
                ColorTokens.primaryOrange.opacity(0.15),
                Color.clear
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        ColorTokens.overlayBackground.ignoresSafeArea()
        PaywallHeroSection(decision: .sampleSoftGate)
    }
}
