import CoreGraphics
import Testing

@testable import MailUI

@Suite("Fold lane")
struct FoldLaneTests {
    /// iPhone Duo's inner display in landscape, in points.
    private let screen = CGRect(x: 0, y: 0, width: 951, height: 669)
    /// The same display with the vertical bar's inset taken off the right.
    private let area = CGRect(x: 0, y: 0, width: 891, height: 669)
    /// The fold down the middle of the inner display while it's partly folded like a book.
    private let bookFold = CGRect(x: 465, y: 0, width: 21, height: 669)

    @Test("With no fold the lane is the whole area")
    func noFold() {
        #expect(FoldLane.lane(in: area, across: screen, folds: []) == area)
    }

    @Test("A fold down the middle leaves the region on its right, though the side bar narrows that region")
    func bookPose() {
        #expect(
            FoldLane.lane(in: area, across: screen, folds: [bookFold])
                == CGRect(x: 486, y: 0, width: 405, height: 669))
    }

    @Test("A fold off the middle leaves the wider region")
    func offCenter() {
        let fold = CGRect(x: 600, y: 0, width: 40, height: 669)
        #expect(
            FoldLane.lane(in: area, across: screen, folds: [fold]) == CGRect(x: 0, y: 0, width: 600, height: 669))
    }

    @Test("A fold across the area, as when the device stands like a laptop, keeps the whole width")
    func tablePose() {
        let fold = CGRect(x: 0, y: 314, width: 951, height: 40)
        #expect(FoldLane.lane(in: area, across: screen, folds: [fold]) == area)
    }

    @Test("A fold outside the area, or along its edge, changes nothing")
    func foldElsewhere() {
        let beyond = CGRect(x: 950, y: 0, width: 40, height: 669)
        let edge = CGRect(x: 880, y: 0, width: 40, height: 669)
        #expect(FoldLane.lane(in: area, across: screen, folds: [beyond, edge]) == area)
    }
}
