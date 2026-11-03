import Foundation

/// Exercise the actual creation-step model without launching a simulator.
@main
struct ProjectCreationNavigationTests {
    struct Failure: Error { let message: String }
    static var checks = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        checks += 1
        if !condition() { throw Failure(message: message) }
    }

    static func main() throws {
        for includesLawn in [false, true] {
            let expected: [ProjectCreationStep] = includesLawn ? [.type, .photos, .lawnMap] : [.type, .photos]
            let steps = ProjectCreationStep.inputSteps(includesLawnMeasurement: includesLawn)
            try expect(steps == expected, "Creation must have only the required input pages")
            try expect(!steps.contains(.generating), "The noninteractive pipeline must not count as an input page")
            try expect(steps.count == (includesLawn ? 3 : 2), "Progress must match the selected flow")

            var forward: [ProjectCreationStep] = [.type]
            while let next = forward.last?.nextInputStep(includesLawnMeasurement: includesLawn) {
                forward.append(next)
                try expect(forward.count <= expected.count, "Forward navigation must terminate without cycling")
            }
            try expect(forward == expected, "Continue must visit the required input pages in order")
            for (index, step) in forward.enumerated() {
                try expect(step.inputPosition(includesLawnMeasurement: includesLawn) == index, "Progress must use the active input position")
            }

            var backward = [expected.last!]
            while let previous = backward.last?.previousInputStep(includesLawnMeasurement: includesLawn) {
                backward.append(previous)
                try expect(backward.count <= expected.count, "Back navigation must terminate without cycling")
            }
            try expect(backward == expected.reversed(), "Back must mirror Continue without an extra details page")
            try expect(ProjectCreationStep.type.previousInputStep(includesLawnMeasurement: includesLawn) == nil, "Back must not leave the first page")
            try expect(ProjectCreationStep.generating.inputPosition(includesLawnMeasurement: includesLawn) == nil, "Saving must not show a navigable progress position")
            try expect(ProjectCreationStep.generating.nextInputStep(includesLawnMeasurement: includesLawn) == nil, "Saving must not advance into inputs")
            try expect(ProjectCreationStep.generating.previousInputStep(includesLawnMeasurement: includesLawn) == nil, "Saving must not navigate back into editable input")
        }
        try expect(ProjectCreationStep.lawnMap.inputPosition(includesLawnMeasurement: false) == nil, "Manual and non-lawn projects must not acquire a map step")
        try expect(ProjectCreationStep.photos.nextInputStep(includesLawnMeasurement: false) == nil, "Standard projects must save from their second page")
        try expect(ProjectCreationStep.photos.nextInputStep(includesLawnMeasurement: true) == .lawnMap, "Paid lawn projects must measure before saving")
        print("PASS: \(checks) project creation navigation checks (two-page flow, lawn measurement, progress and back navigation).")
    }
}
