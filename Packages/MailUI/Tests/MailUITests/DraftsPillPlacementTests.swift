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

    @Test("The dot is 6 points across, centred on the icon")
    func dot() {
        let dot = DraftsPillPlacement.dot(at: CGPoint(x: 40, y: 818))
        #expect(dot.size == CGSize(width: 6, height: 6))
        #expect(dot.midX == 40)
        #expect(dot.midY == 818)
    }
}
