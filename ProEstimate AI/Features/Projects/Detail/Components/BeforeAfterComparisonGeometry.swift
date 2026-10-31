import Foundation
import CoreGraphics

/// Keeps the reveal and hit testing in the same, unchanging image coordinate space.
struct BeforeAfterComparisonGeometry {
    enum DragMode: Equatable {
        case comparison
        case pan
    }

    static let maximumCanvasWidth: CGFloat = 600
    let canvasWidth: CGFloat
    let viewportWidth: CGFloat
    let scale: CGFloat
    let horizontalOffset: CGFloat

    static func clampedFraction(_ fraction: CGFloat) -> CGFloat {
        guard fraction.isFinite else { return 0.5 }
        return min(max(fraction, 0), 1)
    }

    static func fraction(atCanvasX x: CGFloat, width: CGFloat) -> CGFloat? {
        guard x.isFinite, width.isFinite, width > 0 else { return nil }
        return clampedFraction(x / width)
    }

    func fraction(atViewportX x: CGFloat) -> CGFloat? {
        guard viewportWidth.isFinite, scale.isFinite, scale > 0,
              horizontalOffset.isFinite else { return nil }
        let canvasX = (x - viewportWidth / 2 - horizontalOffset) / scale + canvasWidth / 2
        return Self.fraction(atCanvasX: canvasX, width: canvasWidth)
    }

    func dividerViewportX(for fraction: CGFloat) -> CGFloat {
        viewportWidth / 2 + horizontalOffset +
            (Self.clampedFraction(fraction) - 0.5) * canvasWidth * scale
    }

    /// At normal size, a drag anywhere compares. When zoomed, the handle
    /// compares and the rest of the photo pans; the caller locks this choice
    /// for the whole drag so crossing the divider cannot switch behaviors.
    func dragMode(startViewportX: CGFloat, fraction: CGFloat) -> DragMode {
        guard scale > 1 else { return .comparison }
        return abs(startViewportX - dividerViewportX(for: fraction)) <= 22 ? .comparison : .pan
    }

    static func clampedOffset(_ offset: CGSize, canvasSize: CGSize, scale: CGFloat) -> CGSize {
        guard scale.isFinite, scale >= 1,
              canvasSize.width.isFinite, canvasSize.height.isFinite,
              offset.width.isFinite, offset.height.isFinite else { return .zero }
        let horizontalLimit = max(0, canvasSize.width * (scale - 1) / 2)
        let verticalLimit = max(0, canvasSize.height * (scale - 1) / 2)
        return CGSize(
            width: min(max(offset.width, -horizontalLimit), horizontalLimit),
            height: min(max(offset.height, -verticalLimit), verticalLimit)
        )
    }
}
