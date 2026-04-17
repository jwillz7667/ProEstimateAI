import SwiftUI

/// Thin global banner that appears at the top of the app when the device loses
/// network connectivity. Overlaid above tab content so it remains visible across
/// every screen without each feature needing to handle offline state individually.
struct OfflineBanner: View {
    @Environment(NetworkMonitor.self) private var networkMonitor

    var body: some View {
        Group {
            if !networkMonitor.isOnline {
                bannerContent
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: networkMonitor.isOnline)
    }

    private var bannerContent: some View {
        HStack(spacing: SpacingTokens.xs) {
            Image(systemName: "wifi.exclamationmark")
                .font(TypographyTokens.subheadline)

            Text("No internet connection")
                .font(TypographyTokens.subheadline)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, SpacingTokens.md)
        .padding(.vertical, SpacingTokens.xs)
        .background(ColorTokens.warning)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No internet connection")
    }
}
