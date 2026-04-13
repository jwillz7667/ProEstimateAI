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
                    .strokeBorder(ColorTokens.primaryOrange.opacity(0.4), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.08), radius: 3, x: 0, y: 1)
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
            .background(ColorTokens.formFieldBackground, in: RoundedRectangle(cornerRadius: RadiusTokens.small))
            .overlay(
                RoundedRectangle(cornerRadius: RadiusTokens.small)
                    .strokeBorder(ColorTokens.subtleBorder, lineWidth: 1)
            )
            .foregroundStyle(.black)
    }
}
