import SwiftUI

extension View {
    func glassCard(cornerRadius: CGFloat = RadiusTokens.card) -> some View {
        self
            .background(
                ColorTokens.surface,
                in: RoundedRectangle(cornerRadius: cornerRadius)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(ColorTokens.primaryOrange.opacity(0.35), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 3)
            .shadow(color: ColorTokens.primaryOrange.opacity(0.04), radius: 2, x: 0, y: 1)
    }

    func glassSurface(cornerRadius: CGFloat = RadiusTokens.card) -> some View {
        self
            .background(
                ColorTokens.elevatedSurface,
                in: RoundedRectangle(cornerRadius: cornerRadius)
            )
    }

    func formField() -> some View {
        self
            .padding(SpacingTokens.sm)
            .background(ColorTokens.inputBackground, in: RoundedRectangle(cornerRadius: RadiusTokens.small))
            .overlay(
                RoundedRectangle(cornerRadius: RadiusTokens.small)
                    .strokeBorder(ColorTokens.primaryOrange.opacity(0.3), lineWidth: 1)
            )
            .foregroundStyle(ColorTokens.primaryText)
    }
}
