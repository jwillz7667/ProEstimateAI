import SwiftUI

/// Deep-navy "Ready to build?" hero card on the Projects home tab.
/// Single primary CTA opens the AI Remodel Studio (Studio tab).
struct ProjectsHomeHeroCard: View {
    let onStartVision: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.md) {
            Text("Ready to build?")
                .font(TypographyTokens.title)
                .foregroundStyle(ColorTokens.heroForeground)

            Text("Initiate a new project vision or scan a space to get started with professional estimates.")
                .font(TypographyTokens.subheadline)
                .foregroundStyle(ColorTokens.heroForeground.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onStartVision) {
                HStack(spacing: SpacingTokens.xs) {
                    Image(systemName: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                    Text("Start New Vision")
                        .font(TypographyTokens.buttonSecondary)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, SpacingTokens.lg)
                .background(ColorTokens.primaryOrange, in: Capsule())
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Start a new vision")
            .padding(.top, SpacingTokens.xxs)
        }
        .padding(SpacingTokens.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .heroCard()
    }
}
