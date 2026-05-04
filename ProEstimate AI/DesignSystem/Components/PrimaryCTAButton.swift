import SwiftUI

struct PrimaryCTAButton: View {
    let title: String
    var icon: String? = nil
    var isLoading: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: SpacingTokens.xs) {
                if isLoading {
                    ProgressView()
                        .tint(ColorTokens.primaryText)
                } else {
                    if let icon {
                        Image(systemName: icon)
                    }
                    Text(title)
                        .font(TypographyTokens.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, SpacingTokens.sm)
            .padding(.horizontal, SpacingTokens.md)
            .background(
                RoundedRectangle(cornerRadius: RadiusTokens.button)
                    .fill(isDisabled ? ColorTokens.primaryOrange.opacity(0.4) : ColorTokens.primaryOrange)
            )
            .overlay(
                // Slate outline in light mode mirrors the card-text slate so
                // the orange CTA reads as part of the same visual family as
                // the surrounding white card. Skipped in dark mode where the
                // orange already pops against the dark surface.
                RoundedRectangle(cornerRadius: RadiusTokens.button)
                    .strokeBorder(
                        colorScheme == .light ? ColorTokens.primaryText : Color.clear,
                        lineWidth: colorScheme == .light ? 2 : 0
                    )
            )
            // primaryText adapts: slate (#2A323A) in light, system label
            // (white) in dark — preserves dark-mode legibility unchanged.
            .foregroundStyle(ColorTokens.primaryText)
        }
        .disabled(isDisabled || isLoading)
    }
}
