import CoreGraphics
import Testing

@testable import MailUI

@Suite("Drafts pill placement")
struct DraftsPillPlacementTests {
    /// An iPhone's screen in portrait, in points.
    private let bounds = CGRect(x: 0, y: 0, width: 402, height: 874)

    @Test("A pill in the toolbar at the bottom is placed")
    func placedInTheToolbar() {
        #expect(DraftsPillPlacement.isPlaced(CGRect(x: 16, y: 796, width: 76, height: 44), in: bounds))
    }

    @Test(
        "An empty frame, one at the window's origin, or one in the upper half isn't placed",
        arguments: [
            CGRect.zero,
            CGRect(x: 16, y: 796, width: 0, height: 44),
            CGRect(x: 0, y: 0, width: 76, height: 44),
            CGRect(x: 16, y: 300, width: 76, height: 44),
        ])
    func notPlaced(frame: CGRect) {
        #expect(!DraftsPillPlacement.isPlaced(frame, in: bounds))
    }

    /// The button and the containers the iPad's toolbar wraps it in, innermost first, as iOS 27 lays them out.
    private let button = CGRect(x: 14, y: 1151, width: 59, height: 34.5)
    private let glass = CGRect(x: 10, y: 1146, width: 67, height: 44)

    @Test("The glass is the button's first container bigger than it")
    func glassIsTheFirstBiggerContainer() {
        let containers = [button, button, glass, glass, CGRect(x: 0, y: 32, width: 834, height: 1178)]
        #expect(DraftsPillPlacement.glass(around: button, containers: containers) == glass)
    }

    @Test("A container off the button by a rounding error is passed over for the glass")
    func roundingErrorIsPassedOver() {
        let rounded = button.insetBy(dx: -0.000_1, dy: 0)
        #expect(DraftsPillPlacement.glass(around: button, containers: [rounded, glass]) == glass)
    }

    @Test(
        "With no container a platter's margin bigger, the glass is the button's own frame",
        arguments: [
            [CGRect](),
            [CGRect(x: 14, y: 1151, width: 59, height: 34.5)],
            [CGRect(x: 0, y: 32, width: 834, height: 1178)],
            // Bigger one way only: not a platter around the button.
            [CGRect(x: 0, y: 1151, width: 87, height: 34.5)],
        ])
    func glassFallsBackToTheButton(containers: [CGRect]) {
        #expect(DraftsPillPlacement.glass(around: button, containers: containers) == button)
    }

    @Test("Left to right, the corner is at the lane's left, 16 points in, wholly below the screen")
    func cornerLeftToRight() {
        let corner = DraftsPillPlacement.corner(lane: bounds, bounds: bounds, rightToLeft: false)
        #expect(corner.minX == 16)
        #expect(corner.midX < bounds.midX)
        #expect(corner.minY > bounds.maxY)
        #expect(corner.size == DraftsPillPlacement.chipSize)
    }

    @Test("Right to left, the corner is at the lane's right, 16 points in, wholly below the screen")
    func cornerRightToLeft() {
        let corner = DraftsPillPlacement.corner(lane: bounds, bounds: bounds, rightToLeft: true)
        #expect(corner.maxX == bounds.maxX - 16)
        #expect(corner.midX > bounds.midX)
        #expect(corner.minY > bounds.maxY)
    }

    @Test("The corner keeps to a lane narrowed by a fold", arguments: [false, true])
    func cornerInAFoldLane(rightToLeft: Bool) {
        let screen = CGRect(x: 0, y: 0, width: 951, height: 669)
        let lane = CGRect(x: 486, y: 0, width: 405, height: 669)
        let corner = DraftsPillPlacement.corner(lane: lane, bounds: screen, rightToLeft: rightToLeft)
        #expect(lane.minX + 16 <= corner.minX)
        #expect(corner.maxX <= lane.maxX - 16)
        #expect(corner.minY > screen.maxY)
    }
}
