import SwiftUI

extension View {
    func glassCard(cornerRadius: CGFloat = RadiusTokens.card) -> some View {
        self
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: cornerRadius)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(ColorTokens.primaryOrange.opacity(0.12), lineWidth: 0.5)
            )
            .shadow(color: ColorTokens.primaryOrange.opacity(0.04), radius: 3, x: 0, y: 1)
    }

    func glassSurface(cornerRadius: CGFloat = RadiusTokens.card) -> some View {
        self
            .background(
                Color(.tertiarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: cornerRadius)
            )
    }
}
