import SwiftUI
import ImageIO

/// Interactive before/after image comparison slider.
/// The user drags a vertical divider to reveal the "before" image on the
/// left and the "after" (AI-generated) image on the right.
struct BeforeAfterSlider: View {
    let beforeImageURL: URL?
    let afterImageURL: URL?
    let beforeImageData: Data?
    let height: CGFloat
    private let positionBinding: Binding<CGFloat>?
    private let isDragEnabled: Bool
    private let isDraggingExternally: Bool

    @State private var sliderPosition: CGFloat = 0.5
    @Namespace private var comparisonCoordinateSpace
    @GestureState private var isDragging: Bool = false
    @State private var beforePreviewImage: UIImage?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        beforeImageURL: URL?,
        afterImageURL: URL?,
        beforeImageData: Data? = nil,
        height: CGFloat = 280,
        position: Binding<CGFloat>? = nil,
        isDragEnabled: Bool = true,
        isDraggingExternally: Bool = false
    ) {
        self.beforeImageURL = beforeImageURL
        self.afterImageURL = afterImageURL
        self.beforeImageData = beforeImageData
        self.height = height
        self.positionBinding = position
        self.isDragEnabled = isDragEnabled
        self.isDraggingExternally = isDraggingExternally
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let dividerX = width * comparisonPosition

            ZStack(alignment: .leading) {
                // After image (full width, underneath). Both photos use
                // `scaledToFill` + center alignment so the before and
                // after share the exact same crop window — that way
                // the slider blends two views of the same scene rather
                // than two differently-letterboxed canvases.
                afterImage
                    .frame(width: width, height: height, alignment: .center)
                    .clipped()

                // Before image (clipped to left portion)
                beforeImage
                    .frame(width: width, height: height, alignment: .center)
                    .clipped()
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: dividerX, height: height)
                    }

                // Divider line
                dividerView(at: dividerX, totalHeight: height)

                // Labels
                VStack {
                    HStack {
                        Text("Before")
                            .font(TypographyTokens.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, SpacingTokens.xs)
                            .padding(.vertical, SpacingTokens.xxs)
                            .background(.black.opacity(0.5), in: Capsule())
                            .padding(SpacingTokens.sm)

                        Spacer()

                        Text("After")
                            .font(TypographyTokens.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, SpacingTokens.xs)
                            .padding(.vertical, SpacingTokens.xxs)
                            .background(.black.opacity(0.5), in: Capsule())
                            .padding(SpacingTokens.sm)
                    }
                    Spacer()
                }
            }
            // The reveal mask and positioned handle must never change the
            // gesture target's bounds or origin as the divider moves.
            .frame(width: width, height: height)
            .coordinateSpace(.named(comparisonCoordinateSpace))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(comparisonCoordinateSpace))
                    .updating($isDragging) { _, state, _ in
                        state = true
                    }
                    .onChanged { value in
                        guard isDragEnabled,
                              let position = BeforeAfterComparisonGeometry.fraction(atCanvasX: value.location.x, width: width) else { return }
                        setComparisonPosition(position)
                    },
                including: isDragEnabled ? .all : .none
            )
        }
        .frame(maxWidth: BeforeAfterComparisonGeometry.maximumCanvasWidth)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: RadiusTokens.card))
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("before-after-comparison")
        .accessibilityLabel("Before and after comparison")
        .accessibilityValue("\(Int(comparisonPosition * 100)) percent before")
        .accessibilityHint("Swipe up or down to adjust the comparison")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: setComparisonPosition(comparisonPosition + 0.1)
            case .decrement: setComparisonPosition(comparisonPosition - 0.1)
            @unknown default: break
            }
        }
        .task(id: beforeImageData) {
            beforePreviewImage = nil
            guard let data = beforeImageData else { return }
            let image = await Self.makePreview(data)
            guard !Task.isCancelled else { return }
            beforePreviewImage = image
        }
    }

    // MARK: - Subviews

    private var comparisonPosition: CGFloat {
        BeforeAfterComparisonGeometry.clampedFraction(positionBinding?.wrappedValue ?? sliderPosition)
    }

    private func setComparisonPosition(_ position: CGFloat) {
        let clamped = BeforeAfterComparisonGeometry.clampedFraction(position)
        if let positionBinding {
            positionBinding.wrappedValue = clamped
        } else {
            sliderPosition = clamped
        }
    }

    private var beforeImage: some View {
        Group {
            if let uiImage = beforePreviewImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else if let beforeImageURL {
                AsyncImage(url: beforeImageURL) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    placeholderView(label: "Before")
                }
            } else {
                placeholderView(label: "Before")
            }
        }
    }

    private var afterImage: some View {
        Group {
            if let afterImageURL {
                AsyncImage(url: afterImageURL) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    placeholderView(label: "After")
                }
            } else {
                placeholderView(label: "After")
            }
        }
    }

    private func dividerView(at x: CGFloat, totalHeight: CGFloat) -> some View {
        ZStack {
            // Vertical line
            Rectangle()
                .fill(.white)
                .frame(width: 2, height: totalHeight)
                .shadow(color: .black.opacity(0.3), radius: 2)
                .position(x: x, y: totalHeight / 2)

            // Drag handle
            Circle()
                .fill(.white)
                .frame(width: 36, height: 36)
                .shadow(color: .black.opacity(0.3), radius: 4)
                .overlay {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .bold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(.gray)
                }
                .scaleEffect((isDragging || isDraggingExternally) && !reduceMotion ? 1.15 : 1.0)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: isDragging || isDraggingExternally)
                .position(x: x, y: totalHeight / 2)
        }
        .allowsHitTesting(false)
    }

    private func placeholderView(label: String) -> some View {
        Rectangle()
            .fill(ColorTokens.inputBackground)
            .overlay {
                VStack(spacing: SpacingTokens.xs) {
                    Image(systemName: "photo")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text(label)
                        .font(TypographyTokens.caption)
                        .foregroundStyle(.secondary)
                }
            }
    }

    private nonisolated static func makePreview(_ data: Data) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceShouldCacheImmediately: true,
                    kCGImageSourceThumbnailMaxPixelSize: 2048,
                  ] as CFDictionary) else { return nil }
            return UIImage(cgImage: image)
        }.value
    }
}

// MARK: - Preview

#Preview {
    BeforeAfterSlider(
        beforeImageURL: nil,
        afterImageURL: nil
    )
    .padding()
}
