import SwiftUI

extension View {
    /// Default soft white card surface with hairline stroke and ambient shadow.
    /// Used by `GlassCard` and the new card layouts across Projects, Studio, Quotes.
    func glassCard(cornerRadius: CGFloat = RadiusTokens.card) -> some View {
        background(
            ColorTokens.surface,
            in: RoundedRectangle(cornerRadius: cornerRadius)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(ColorTokens.cardStroke, lineWidth: 1)
        )
        .shadow(ShadowTokens.small)
    }

    /// Higher-emphasis pressable surface (e.g., row actions, sheet anchors).
    func glassSurface(cornerRadius: CGFloat = RadiusTokens.card) -> some View {
        background(
            ColorTokens.elevatedSurface,
            in: RoundedRectangle(cornerRadius: cornerRadius)
        )
        .shadow(ShadowTokens.medium)
    }

    /// Deep navy hero card (the "Ready to build?" surface and paywall hero).
    func heroCard(cornerRadius: CGFloat = RadiusTokens.hero) -> some View {
        background(
            ColorTokens.heroBackground,
            in: RoundedRectangle(cornerRadius: cornerRadius)
        )
        .shadow(ShadowTokens.hero)
    }

    /// Bordered light input field — used by auth screens and inline forms.
    func formField() -> some View {
        padding(.vertical, SpacingTokens.sm + 2)
            .padding(.horizontal, SpacingTokens.md)
            .background(ColorTokens.inputBackground, in: RoundedRectangle(cornerRadius: RadiusTokens.input))
            .overlay(
                RoundedRectangle(cornerRadius: RadiusTokens.input)
                    .strokeBorder(ColorTokens.cardStroke, lineWidth: 1)
            )
            .foregroundStyle(ColorTokens.textPrimary)
    }
}
