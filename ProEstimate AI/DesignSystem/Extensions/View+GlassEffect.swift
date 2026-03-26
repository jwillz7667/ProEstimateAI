import SwiftUI

extension View {
    func glassCard(cornerRadius: CGFloat = RadiusTokens.card) -> some View {
        self
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
            )
    }

    func glassSurface(cornerRadius: CGFloat = RadiusTokens.card) -> some View {
        self
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
    }
}
