import SwiftUI

/// Top-of-dashboard hero card hosting a silent, gaplessly-looping promo
/// video. Replaces the previous subscription upgrade banner — pure
/// visual hook, no overlays or tap handlers — and is intentionally
/// taller than the banner it replaces so the rest of the dashboard
/// content reflows down a screen-third.
///
/// The "curved screen" effect is built from three layers:
/// 1. A continuous-corner clip mask shaped like a phone/tablet bezel.
/// 2. A subtle dark stroke (the bezel itself) that catches highlights
///    around the curve.
/// 3. A radial sheen + ambient drop shadow that imitate light bouncing
///    off a glass display, giving the otherwise-flat video a soft
///    physical presence on the surface.
///
/// The video aspect (1080×720 = 3:2) is enforced via `Color.clear` +
/// `aspectRatio(.fit)` so the card height tracks whatever width the
/// parent gives it without ever distorting the image.
struct DashboardHeroVideoCard: View {
    @State private var isPlaying = true

    private let cornerRadius: CGFloat = 28
    private let videoAspect: CGFloat = 1080.0 / 720.0

    var body: some View {
        Color.clear
            .aspectRatio(videoAspect, contentMode: .fit)
            .overlay {
                LoopingVideoPlayer(
                    resourceName: "dashboard_hero",
                    resourceExtension: "mp4",
                    isPlaying: $isPlaying
                )
            }
            .overlay { glassSheen }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay { bezelStroke }
            .shadow(color: .black.opacity(0.32), radius: 18, x: 0, y: 10)
            .shadow(color: ColorTokens.primaryOrange.opacity(0.12), radius: 24, x: 0, y: 6)
            .onAppear { isPlaying = true }
            .onDisappear { isPlaying = false }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("ProEstimate AI promo video")
    }

    /// Soft top-leading highlight + bottom-trailing falloff that read as
    /// a glass screen reflection. Kept faint (≤ 12% white) so it doesn't
    /// fight the underlying video for attention.
    private var glassSheen: some View {
        LinearGradient(
            colors: [
                Color.white.opacity(0.12),
                Color.white.opacity(0.0),
                Color.black.opacity(0.0),
                Color.black.opacity(0.18),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .blendMode(.softLight)
        .allowsHitTesting(false)
    }

    /// Two-tone bezel: a thin warm-orange inner halo (matches the brand
    /// accent and reinforces "this is our app's screen"), backstopped
    /// by a near-black outer ring that defines the curved edge in dark
    /// surroundings.
    private var bezelStroke: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.22),
                            Color.white.opacity(0.04),
                            ColorTokens.primaryOrange.opacity(0.25),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .inset(by: 1)
                .strokeBorder(Color.black.opacity(0.55), lineWidth: 0.75)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        DashboardHeroVideoCard()
            .padding()
    }
    .background(ColorTokens.background)
}
