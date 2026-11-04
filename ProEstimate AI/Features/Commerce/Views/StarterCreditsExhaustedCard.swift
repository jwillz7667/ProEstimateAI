import SwiftUI

/// Explains the paid AI boundary without implying that an unpaid account has
/// exhausted credits or started an Apple trial automatically.
struct StarterCreditsExhaustedCard: View {
    var isVisible: Bool

    var body: some View {
        if isVisible {
            HStack(spacing: SpacingTokens.md) {
                ZStack {
                    Circle()
                        .fill(ColorTokens.primaryOrange.opacity(0.18))
                        .frame(width: 44, height: 44)
                    Image(systemName: "sparkles")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(ColorTokens.primaryOrange)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("AI previews are included with Pro")
                        .font(TypographyTokens.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(ColorTokens.primaryText)

                    Text("Start an eligible three-day trial or subscribe. Your basic workspace stays free.")
                        .font(TypographyTokens.footnote)
                        .foregroundStyle(ColorTokens.secondaryText)
                }

                Spacer(minLength: 0)
            }
            .padding(SpacingTokens.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: RadiusTokens.card, style: .continuous)
                    .fill(ColorTokens.primaryOrange.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: RadiusTokens.card, style: .continuous)
                    .strokeBorder(ColorTokens.primaryOrange.opacity(0.35), lineWidth: 1)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("AI previews require an active trial or subscription. Basic project tools remain free.")
        }
    }
}

#Preview {
    StarterCreditsExhaustedCard(isVisible: true)
        .padding()
        .background(ColorTokens.background)
}
