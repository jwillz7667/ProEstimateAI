import SwiftUI

struct GlassCard<Content: View>: View {
    let cornerRadius: CGFloat
    @ViewBuilder let content: () -> Content

    init(
        cornerRadius: CGFloat = RadiusTokens.card,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.content = content
    }

    var body: some View {
        content()
            .padding(SpacingTokens.md)
            .glassCard(cornerRadius: cornerRadius)
    }
}
