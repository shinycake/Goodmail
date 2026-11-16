import CoreGraphics
import Testing

@testable import MailUI

@Suite("Fold lane")
struct FoldLaneTests {
    /// iPhone Duo's inner display in landscape, in points, with its vertical bar's inset taken off the right.
    private let area = CGRect(x: 0, y: 0, width: 900, height: 669)
    /// The fold down the middle of the inner display while it's partly folded like a book.
    private let bookFold = CGRect(x: 430, y: 0, width: 40, height: 669)

    @Test("With no fold the lane is the whole area")
    func noFold() {
        #expect(FoldLane.lane(in: area, folds: []) == area)
    }

    @Test("A fold down the middle leaves the region on its right")
    func bookPose() {
        #expect(FoldLane.lane(in: area, folds: [bookFold]) == CGRect(x: 470, y: 0, width: 430, height: 669))
    }

    @Test("A fold off the middle leaves the wider region")
    func offCenter() {
        let fold = CGRect(x: 600, y: 0, width: 40, height: 669)
        #expect(FoldLane.lane(in: area, folds: [fold]) == CGRect(x: 0, y: 0, width: 600, height: 669))
    }

    @Test("A fold across the area, as when the device stands like a laptop, keeps the whole width")
    func tablePose() {
        let fold = CGRect(x: 0, y: 314, width: 900, height: 40)
        #expect(FoldLane.lane(in: area, folds: [fold]) == area)
    }

    @Test("A fold outside the area, or along its edge, changes nothing")
    func foldElsewhere() {
        let beyond = CGRect(x: 950, y: 0, width: 40, height: 669)
        let edge = CGRect(x: 880, y: 0, width: 40, height: 669)
        #expect(FoldLane.lane(in: area, folds: [beyond, edge]) == area)
    }
}
