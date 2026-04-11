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
                    .strokeBorder(ColorTokens.subtleBorder, lineWidth: 0.5)
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
}
