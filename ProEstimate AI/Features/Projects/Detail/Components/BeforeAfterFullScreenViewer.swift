import SwiftUI

/// Full-screen, dismissable presentation of the before/after slider.
///
/// When the contractor taps the inline slider on a project detail or
/// quick-generate screen, this view presents a larger version with
/// pinch-to-zoom and pan, plus a header showing the prompt that
/// produced the AI preview. The interactive divider behavior is
/// rendered by `BeforeAfterSlider`, with one owner for drag recognition so
/// fullscreen panning cannot interrupt the comparison halfway through a drag.
struct BeforeAfterFullScreenViewer: View {
    let beforeImageURL: URL?
    let afterImageURL: URL?
    var beforeImageData: Data?
    /// Optional caption rendered under the slider — e.g. the AI prompt
    /// that generated the "after" image, so the contractor can recall
    /// what they asked for while showing the comparison to a client.
    var caption: String?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var zoom: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var comparisonPosition: CGFloat = 0.5
    @Namespace private var viewportCoordinateSpace
    @GestureState private var magnificationStart: CGFloat? = nil
    @GestureState private var dragContext: ComparisonDragContext? = nil

    private struct ComparisonDragContext {
        let mode: BeforeAfterComparisonGeometry.DragMode
        let initialOffset: CGSize
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { geometry in
                let availableWidth = geometry.size.width
                // Use the actual capped image width on iPad, rather than
                // treating the empty margins as part of the reveal canvas.
                let canvasWidth = min(availableWidth, BeforeAfterComparisonGeometry.maximumCanvasWidth)
                let availableHeight = geometry.size.height * 0.85
                let height = min(canvasWidth * 1.25, availableHeight)
                let canvasSize = CGSize(width: canvasWidth, height: height)
                let comparisonGeometry = BeforeAfterComparisonGeometry(
                    canvasWidth: canvasWidth,
                    viewportWidth: availableWidth,
                    scale: zoom,
                    horizontalOffset: offset.width
                )
                VStack(spacing: SpacingTokens.md) {
                    Spacer(minLength: 0)

                    BeforeAfterSlider(
                        beforeImageURL: beforeImageURL,
                        afterImageURL: afterImageURL,
                        beforeImageData: beforeImageData,
                        height: height,
                        position: $comparisonPosition,
                        isDragEnabled: false,
                        isDraggingExternally: dragContext?.mode == .comparison
                    )
                    .scaleEffect(zoom)
                    .offset(offset)
                    .gesture(comparisonDrag(geometry: comparisonGeometry, canvasSize: canvasSize))
                    .simultaneousGesture(
                        MagnifyGesture()
                            .updating($magnificationStart) { _, start, _ in
                                if start == nil { start = zoom }
                            }
                            .onChanged { value in
                                zoom = min(max((magnificationStart ?? zoom) * value.magnification, 1), 4)
                                offset = BeforeAfterComparisonGeometry.clampedOffset(offset, canvasSize: canvasSize, scale: zoom)
                            }
                    )
                    .onTapGesture(count: 2) {
                        // Double-tap to reset zoom — common iOS convention.
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                            zoom = 1.0
                            offset = .zero
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
                .coordinateSpace(.named(viewportCoordinateSpace))
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
                Text(zoom == 1
                     ? "Drag to slide · pinch to zoom · double-tap to reset"
                     : "Drag the divider to compare · drag the photo to pan · double-tap to reset")
                    .font(TypographyTokens.caption2)
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, SpacingTokens.md)
                    .padding(.bottom, SpacingTokens.lg)
            }
        }
        .statusBarHidden()
    }

    private func comparisonDrag(geometry: BeforeAfterComparisonGeometry, canvasSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(viewportCoordinateSpace))
            .updating($dragContext) { value, context, _ in
                guard magnificationStart == nil else { return }
                if context == nil {
                    context = ComparisonDragContext(
                        mode: geometry.dragMode(startViewportX: value.startLocation.x, fraction: comparisonPosition),
                        initialOffset: offset
                    )
                }
            }
            .onChanged { value in
                guard magnificationStart == nil else { return }
                let context = dragContext ?? ComparisonDragContext(
                    mode: geometry.dragMode(startViewportX: value.startLocation.x, fraction: comparisonPosition),
                    initialOffset: offset
                )
                switch context.mode {
                case .comparison:
                    if let fraction = geometry.fraction(atViewportX: value.location.x) {
                        comparisonPosition = fraction
                    }
                case .pan:
                    offset = BeforeAfterComparisonGeometry.clampedOffset(
                        CGSize(width: context.initialOffset.width + value.translation.width,
                               height: context.initialOffset.height + value.translation.height),
                        canvasSize: canvasSize,
                        scale: zoom
                    )
                }
            }
    }
}

#Preview {
    BeforeAfterFullScreenViewer(
        beforeImageURL: nil,
        afterImageURL: nil,
        caption: "Modern kitchen with white shaker cabinets, quartz counters, brass fixtures"
    )
}
