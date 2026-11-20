import Foundation
import PlaneGame
import Testing

/// The arrows steer and Space fires, for as long as they are held.
struct KeysTests {
    private let width: CGFloat = 400
    private let frame: TimeInterval = 1.0 / 60
    private var fullSlide: CGFloat { width * PlaneGameKeys.lanesPerSecond * CGFloat(frame) }

    /// Steps `count` frames and gives what each one did.
    private func run(_ keys: inout PlaneGameKeys, frames count: Int) -> [PlaneGameInput] {
        (0..<count).map { _ in keys.advance(by: frame, fieldWidth: width) }
    }

    @Test func noKeysDoNothing() {
        var keys = PlaneGameKeys()
        #expect(run(&keys, frames: 3) == Array(repeating: PlaneGameInput(), count: 3))
    }

    @Test(arguments: [(PlaneGameKeys.Key.left, -1.0), (.right, 1.0)])
    func aHeldArrowGlidesItsWayAtFullSpeedOnceEasedIn(key: PlaneGameKeys.Key, sign: Double) throws {
        var keys = PlaneGameKeys()
        keys.press(key)
        let slides = run(&keys, frames: 30).map(\.slide)
        let last = try #require(slides.last)
        #expect(abs(last - CGFloat(sign) * fullSlide) < 0.0001)
        #expect(slides.allSatisfy { $0 * CGFloat(sign) > 0 })
    }

    @Test func aHeldArrowEasesIn() {
        var keys = PlaneGameKeys()
        keys.press(.right)
        let slides = run(&keys, frames: 12).map(\.slide)
        #expect(slides[0] < slides[1])
        #expect(slides[1] < slides[2])
        #expect(slides[0] < fullSlide / 2)
        #expect(slides[11] == fullSlide)
    }

    @Test func bothArrowsHeldSteerNowhere() {
        var keys = PlaneGameKeys()
        keys.press(.left)
        keys.press(.right)
        #expect(run(&keys, frames: 20).allSatisfy { $0.slide == 0 })
    }

    @Test func lettingGoOfOneOfBothArrowsSteersTheOtherWayFromAStandstill() throws {
        var keys = PlaneGameKeys()
        keys.press(.left)
        keys.press(.right)
        _ = run(&keys, frames: 20)
        keys.release(.left)
        let slides = run(&keys, frames: 2).map(\.slide)
        #expect(slides[0] > 0)
        #expect(slides[0] < fullSlide / 2)
    }

    @Test func releasingStopsThePlaneAtOnce() {
        var keys = PlaneGameKeys()
        keys.press(.right)
        _ = run(&keys, frames: 20)
        keys.release(.right)
        #expect(run(&keys, frames: 2).allSatisfy { $0.slide == 0 })
    }

    @Test func aTapQuickerThanAFrameStillNudgesOnceAndTheNextTapEasesInAgain() {
        var keys = PlaneGameKeys()
        keys.press(.left)
        keys.release(.left)
        let nudge = keys.advance(by: frame, fieldWidth: width).slide
        #expect(nudge < 0)
        #expect(abs(nudge) < fullSlide / 2)
        #expect(keys.advance(by: frame, fieldWidth: width).slide == 0)
        keys.press(.left)
        keys.release(.left)
        #expect(keys.advance(by: frame, fieldWidth: width).slide == nudge)
    }

    @Test func theSpeedScalesWithTheFieldWidth() {
        var narrow = PlaneGameKeys()
        var wide = PlaneGameKeys()
        narrow.press(.right)
        wide.press(.right)
        let one = narrow.advance(by: 1, fieldWidth: 300).slide
        let three = wide.advance(by: 1, fieldWidth: 900).slide
        #expect(abs(three - 3 * one) < 0.0001)
    }

    @Test func turningRoundEasesInAgain() {
        var keys = PlaneGameKeys()
        keys.press(.right)
        _ = run(&keys, frames: 20)
        keys.release(.right)
        keys.press(.left)
        let turn = keys.advance(by: frame, fieldWidth: width).slide
        #expect(turn < 0)
        #expect(abs(turn) < fullSlide / 2)
    }

    @Test func spaceFiresForAsLongAsItIsHeld() {
        var keys = PlaneGameKeys()
        keys.press(.fire)
        #expect(run(&keys, frames: 30).allSatisfy { $0.isFiring })
        keys.release(.fire)
        #expect(run(&keys, frames: 2).allSatisfy { !$0.isFiring })
    }

    @Test func aTapOnSpaceQuickerThanAFrameFiresForThatFrame() {
        var keys = PlaneGameKeys()
        keys.press(.fire)
        keys.release(.fire)
        #expect(run(&keys, frames: 3).map(\.isFiring) == [true, false, false])
    }

    @Test func firingAndSteeringAreIndependent() {
        var keys = PlaneGameKeys()
        keys.press(.fire)
        keys.press(.left)
        let input = run(&keys, frames: 30).last
        #expect(input?.isFiring == true)
        #expect(input?.slide == -fullSlide)
    }

    @Test func releasingAllLetsGoOfEveryKeyAndForgetsTaps() {
        var keys = PlaneGameKeys()
        keys.press(.left)
        keys.press(.fire)
        _ = run(&keys, frames: 20)
        keys.press(.right)
        keys.releaseAll()
        #expect(run(&keys, frames: 3) == Array(repeating: PlaneGameInput(), count: 3))
    }

    @Test func noTimeOrNoFieldMovesNothing() {
        var keys = PlaneGameKeys()
        keys.press(.right)
        #expect(keys.advance(by: 0, fieldWidth: width).slide == 0)
        #expect(keys.advance(by: frame, fieldWidth: .nan).slide == 0)
        #expect(keys.advance(by: frame, fieldWidth: -5).slide == 0)
    }
}
