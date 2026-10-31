import Foundation
import CoreGraphics

@main
struct BeforeAfterComparisonTests {
    enum Failure: Error {
        case assertion(String)
    }

    static var checks = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        checks += 1
        guard condition() else { throw Failure.assertion(message) }
    }

    static func main() throws {
        // Overshoot and reversal must reveal an entire image at each edge,
        // then continue smoothly without resetting at the halfway point.
        let locations: [CGFloat] = [-120, 0, 60, 150, 300, 450, 600, 730, 450, 300, 150, 0, -80, 300, 600]
        let expected: [CGFloat] = [0, 0, 0.1, 0.25, 0.5, 0.75, 1, 1, 0.75, 0.5, 0.25, 0, 0, 0.5, 1]
        for (x, fraction) in zip(locations, expected) {
            try expect(BeforeAfterComparisonGeometry.fraction(atCanvasX: x, width: 600) == fraction,
                       "Drag at \(x) must produce \(fraction), including after reversing")
        }
        try expect(BeforeAfterComparisonGeometry.fraction(atCanvasX: 10, width: 0) == nil,
                   "A transient zero-width layout must not replace the reveal position")
        try expect(BeforeAfterComparisonGeometry.fraction(atCanvasX: .nan, width: 600) == nil,
                   "Invalid event coordinates must not corrupt view state")

        // On iPad the 600-point photo sits inside a wider fullscreen viewport.
        let tablet = BeforeAfterComparisonGeometry(canvasWidth: 600, viewportWidth: 1024, scale: 1, horizontalOffset: 0)
        for (x, fraction): (CGFloat, CGFloat) in [(0, 0), (212, 0), (512, 0.5), (812, 1), (1024, 1)] {
            try expect(tablet.fraction(atViewportX: x) == fraction,
                       "Tablet margins must not count as reveal-image width")
        }

        // A zoomed/panned image needs the inverse transform, not viewport x / width.
        let zoomed = BeforeAfterComparisonGeometry(canvasWidth: 600, viewportWidth: 1024, scale: 2, horizontalOffset: 120)
        for (x, fraction): (CGFloat, CGFloat) in [(32, 0), (332, 0.25), (632, 0.5), (932, 0.75), (1232, 1)] {
            try expect(zoomed.fraction(atViewportX: x) == fraction,
                       "Zoom and pan must not cause a jump or premature clipping")
            try expect(zoomed.dividerViewportX(for: fraction) == x,
                       "The drag target and rendered divider must use the same transform")
        }

        try expect(tablet.dragMode(startViewportX: 300, fraction: 0.5) == .comparison,
                   "Normal-size dragging must always compare, never start a competing pan")
        try expect(zoomed.dragMode(startViewportX: 632, fraction: 0.5) == .comparison,
                   "The zoomed divider handle must remain adjustable")
        try expect(zoomed.dragMode(startViewportX: 654, fraction: 0.5) == .comparison,
                   "The divider must have a 44-point minimum touch target")
        try expect(zoomed.dragMode(startViewportX: 655, fraction: 0.5) == .pan,
                   "Dragging a zoomed photo away from the handle must pan")
        let bounds = BeforeAfterComparisonGeometry.clampedOffset(CGSize(width: 900, height: -900),
                                                                 canvasSize: CGSize(width: 600, height: 750), scale: 2)
        try expect(bounds == CGSize(width: 300, height: -375), "Panning must stop at the photo edges")
        try expect(BeforeAfterComparisonGeometry.clampedOffset(bounds, canvasSize: CGSize(width: 600, height: 750), scale: 1) == .zero,
                   "Returning to normal zoom must remove residual pan offsets")

        print("PASS: \(checks) comparison checks (full reveal, overshoot/reversal, tablet margins, zoom/pan transforms and gesture routing)")
    }
}
