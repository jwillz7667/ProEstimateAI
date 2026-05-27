import SwiftUI

/// Soft white card with hairline stroke and ambient shadow.
/// Wraps content with default `SpacingTokens.lg` interior padding.
struct GlassCard<Content: View>: View {
    let cornerRadius: CGFloat
    let interiorPadding: CGFloat
    @ViewBuilder let content: () -> Content

    init(
        cornerRadius: CGFloat = RadiusTokens.card,
        interiorPadding: CGFloat = SpacingTokens.lg,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.interiorPadding = interiorPadding
        self.content = content
    }

    var body: some View {
        content()
            .padding(interiorPadding)
            .glassCard(cornerRadius: cornerRadius)
    }
}
