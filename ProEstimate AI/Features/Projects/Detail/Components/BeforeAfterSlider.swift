import SwiftUI

/// Interactive before/after image comparison slider.
/// The user drags a vertical divider to reveal the "before" image on the
/// left and the "after" (AI-generated) image on the right.
struct BeforeAfterSlider: View {
    let beforeImageURL: URL?
    let afterImageURL: URL?
    let beforeImageData: Data?
    let height: CGFloat

    @State private var sliderPosition: CGFloat = 0.5
    @GestureState private var isDragging: Bool = false

    init(
        beforeImageURL: URL?,
        afterImageURL: URL?,
        beforeImageData: Data? = nil,
        height: CGFloat = 280
    ) {
        self.beforeImageURL = beforeImageURL
        self.afterImageURL = afterImageURL
        self.beforeImageData = beforeImageData
        self.height = height
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let dividerX = width * sliderPosition

            ZStack {
                // After image (full width, underneath)
                afterImage
                    .frame(width: width, height: height)
                    .clipped()

                // Before image (clipped to left portion)
                beforeImage
                    .frame(width: width, height: height)
                    .clipped()
                    .clipShape(
                        HorizontalClipShape(width: dividerX)
                    )

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
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isDragging) { _, state, _ in
                        state = true
                    }
                    .onChanged { value in
                        let newPosition = value.location.x / width
                        sliderPosition = min(max(newPosition, 0.05), 0.95)
                    }
            )
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: RadiusTokens.card))
    }

    // MARK: - Subviews

    private var beforeImage: some View {
        Group {
            if let beforeImageData, let uiImage = UIImage(data: beforeImageData) {
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
                .scaleEffect(isDragging ? 1.15 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: isDragging)
                .position(x: x, y: totalHeight / 2)
        }
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
}

// MARK: - Clip Shape

/// Custom shape that clips to a rectangle from the leading edge
/// to a specified width.
private struct HorizontalClipShape: Shape {
    let width: CGFloat

    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: 0, y: 0, width: width, height: rect.height))
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
