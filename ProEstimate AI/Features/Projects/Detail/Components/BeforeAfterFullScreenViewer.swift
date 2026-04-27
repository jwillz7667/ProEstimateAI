import SwiftUI

/// Full-screen, dismissable presentation of the before/after slider.
///
/// When the contractor taps the inline slider on a project detail or
/// quick-generate screen, this view presents a larger version with
/// pinch-to-zoom and pan, plus a header showing the prompt that
/// produced the AI preview. The interactive divider behavior is
/// inherited from `BeforeAfterSlider`.
struct BeforeAfterFullScreenViewer: View {
    let beforeImageURL: URL?
    let afterImageURL: URL?
    var beforeImageData: Data?
    /// Optional caption rendered under the slider — e.g. the AI prompt
    /// that generated the "after" image, so the contractor can recall
    /// what they asked for while showing the comparison to a client.
    var caption: String?

    @Environment(\.dismiss) private var dismiss
    @State private var zoom: CGFloat = 1.0
    @State private var lastZoom: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { geometry in
                let height = geometry.size.height * 0.78
                VStack(spacing: SpacingTokens.md) {
                    Spacer(minLength: 0)

                    BeforeAfterSlider(
                        beforeImageURL: beforeImageURL,
                        afterImageURL: afterImageURL,
                        beforeImageData: beforeImageData,
                        height: height
                    )
                    .scaleEffect(zoom)
                    .offset(offset)
                    .gesture(
                        SimultaneousGesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    let scaled = lastZoom * value
                                    zoom = max(1.0, min(scaled, 4.0))
                                }
                                .onEnded { _ in lastZoom = zoom },
                            DragGesture()
                                .onChanged { value in
                                    // Only allow panning while zoomed in,
                                    // otherwise pan would fight the slider's
                                    // own drag gesture.
                                    guard zoom > 1.0 else { return }
                                    offset = CGSize(
                                        width: lastOffset.width + value.translation.width,
                                        height: lastOffset.height + value.translation.height
                                    )
                                }
                                .onEnded { _ in lastOffset = offset }
                        )
                    )
                    .onTapGesture(count: 2) {
                        // Double-tap to reset zoom — common iOS convention.
                        withAnimation(.easeInOut(duration: 0.2)) {
                            zoom = 1.0
                            lastZoom = 1.0
                            offset = .zero
                            lastOffset = .zero
                        }
                    }

                    if let caption, !caption.isEmpty {
                        Text(caption)
                            .font(TypographyTokens.caption)
                            .foregroundStyle(.white.opacity(0.75))
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .padding(.horizontal, SpacingTokens.lg)
                    }

                    Spacer(minLength: 0)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }

            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(.black.opacity(0.45), in: Circle())
                            .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
                    }
                    .padding(SpacingTokens.md)
                    .accessibilityLabel("Close before/after comparison")
                }
                Spacer()
                if zoom == 1.0 {
                    Text("Drag to slide · pinch to zoom · double-tap to reset")
                        .font(TypographyTokens.caption2)
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.bottom, SpacingTokens.lg)
                }
            }
        }
        .statusBarHidden()
    }
}

#Preview {
    BeforeAfterFullScreenViewer(
        beforeImageURL: nil,
        afterImageURL: nil,
        caption: "Modern kitchen with white shaker cabinets, quartz counters, brass fixtures"
    )
}
