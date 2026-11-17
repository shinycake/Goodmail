import CoreGraphics
import Foundation
import Testing

@testable import MailUI

/// The welcome screen's stage answers a touch: the doodles shy away, the envelopes hop and a paper plane flies off.
/// All of it is worked out from the time, and all of it has settled or left a few seconds later.
struct WelcomeSceneTests {
    /// A moment between two of the planes that pass by themselves, so the only planes are the ones a test sends.
    private let landing = Date(timeIntervalSinceReferenceDate: 57_142_857 * WelcomeScene.passEvery + 6)
    private let size = CGSize(width: 402, height: 350)
    private let center = CGPoint(x: 201, y: 175)

    private func touch(at origin: CGPoint, after elapsed: TimeInterval) -> WelcomeTouch {
        WelcomeTouch(origin: origin, elapsed: elapsed, number: 0)
    }

    /// The stage `elapsed` seconds after a poke landed `offset` from its middle, or holding still for Reduce Motion
    /// when `elapsed` is `nil`.
    private func scene(
        pokedAt offset: CGSize? = nil, after elapsed: TimeInterval?, rightToLeft: Bool = false
    ) -> WelcomeScene {
        WelcomeScene(
            size: size, pokes: offset.map { [WelcomePoke(offset: $0, time: landing, number: 0)] } ?? [],
            clock: elapsed.map { .running(landing + $0) } ?? .stopped, rightToLeft: rightToLeft)
    }

    // MARK: Touches

    @Test func aFlurryOfTapsKeepsOnlyItsLastFew() {
        var pokes = WelcomePokes()
        for tap in 0..<6 {
            pokes.land(offset: CGSize(width: tap, height: 0), time: landing + Double(tap) * 0.1)
        }
        #expect(pokes.live.map(\.number) == [2, 3, 4, 5])
    }

    @Test func aTouchThatHasPlayedOutIsDroppedWhenTheNextLands() {
        var pokes = WelcomePokes()
        pokes.land(offset: .zero, time: landing)
        pokes.land(offset: .zero, time: landing + 1)
        pokes.land(offset: .zero, time: landing + WelcomePoke.lifetime + 0.5)
        #expect(pokes.live.map(\.number) == [1, 2])
    }

    // MARK: What a touch sets off

    @Test func nothingMovesBeforeTheTouchLands() {
        let early = touch(at: center, after: -0.2)
        #expect(early.push(on: CGPoint(x: 260, y: 175)) == .zero)
        #expect(early.hop(around: center) == 0)
        #expect(early.flight(in: size, rightToLeft: false) == nil)
    }

    @Test func aTouchPushesWhatIsNearItAway() {
        let push = touch(at: center, after: 0.2).push(on: CGPoint(x: 260, y: 175))
        #expect(push.width > 5)
        #expect(push.height == 0)
        let pushLeft = touch(at: center, after: 0.2).push(on: CGPoint(x: 142, y: 175))
        #expect(pushLeft.width == -push.width)
    }

    @Test func theEnvelopesHopMoreTheNearerTheTouch() {
        let near = touch(at: center, after: 0.1).hop(around: center)
        let far = touch(at: CGPoint(x: 20, y: 20), after: 0.1).hop(around: center)
        #expect(near > 0.8)
        #expect(far > 0.2)
        #expect(far < near / 2)
    }

    @Test func everythingATouchSetsOffHasSettledByTheEndOfItsLife() {
        let spent = touch(at: center, after: WelcomePoke.lifetime)
        #expect(abs(spent.push(on: CGPoint(x: 260, y: 175)).width) < 0.01)
        #expect(abs(spent.hop(around: center)) < 0.001)
        #expect(spent.flight(in: size, rightToLeft: false) == nil)
    }

    // MARK: The paper plane

    @Test func aPlaneTakesOffFromUnderTheFingerAndLeavesByTheTrailingEdge() throws {
        let origin = CGPoint(x: 120, y: 200)
        let takeoff = try #require(touch(at: origin, after: 0).flight(in: size, rightToLeft: false))
        #expect(takeoff.position == origin)
        #expect(takeoff.opacity == 0)

        let midway = try #require(
            touch(at: origin, after: WelcomePoke.flightTime / 2).flight(in: size, rightToLeft: false))
        #expect(midway.opacity == 1)
        #expect(midway.trail.first == midway.position)

        let leaving = try #require(
            touch(at: origin, after: WelcomePoke.flightTime).flight(in: size, rightToLeft: false))
        #expect(leaving.position.x > size.width)
        #expect(leaving.position.y < origin.y)
    }

    @Test func inARightToLeftLanguageThePlaneLeavesToTheLeft() throws {
        let leaving = try #require(
            touch(at: CGPoint(x: 120, y: 200), after: WelcomePoke.flightTime).flight(in: size, rightToLeft: true))
        #expect(leaving.position.x < 0)
        // Flying left, it points left.
        #expect(abs(leaving.heading) > .pi / 2)
    }

    @Test func nowAndThenAPlanePassesByItself() throws {
        let passing = try #require(scene(after: WelcomeScene.passEvery - 6 + 0.1).flights.first)
        // It comes in from beyond the leading edge, and has gone long before the next one.
        #expect(passing.position.x < 0)
        #expect(scene(after: WelcomeScene.passEvery - 6 + WelcomeScene.passTime + 0.1).flights.isEmpty)
        let mirrored = try #require(scene(after: WelcomeScene.passEvery - 6 + 0.1, rightToLeft: true).flights.first)
        #expect(mirrored.position.x > size.width)
    }

    // MARK: The stage

    @Test func withReduceMotionEverythingRestsInPlaceWhateverIsTouched() {
        let still = scene(pokedAt: .zero, after: nil)
        #expect(still.fan == 1)
        #expect(still.lift == 0)
        #expect(still.flights.isEmpty)
        #expect(still.sway(phase: 1.7) == 0)
        #expect(still.position(anchor: CGPoint(x: 0.25, y: 0.1), phase: 1.7) == CGPoint(x: 100.5, y: 35))
    }

    @Test func aTapOnTheEnvelopesSwingsTheFanOpenAndSendsAPlaneFromThem() {
        let tapped = scene(pokedAt: .zero, after: 0.1)
        #expect(tapped.fan > 1.3)
        #expect(tapped.lift > 5)
        #expect(tapped.flights.count == 1)
        #expect(scene(pokedAt: .zero, after: 0).flights.first?.position == center)

        let later = scene(pokedAt: .zero, after: WelcomePoke.lifetime)
        // Back to breathing and bobbing about their place.
        #expect(abs(later.fan - 1) < 0.05)
        #expect(abs(later.lift) < 3.1)
        #expect(later.flights.isEmpty)
    }

    @Test func aTapBesideADoodlePushesItAwayAndItComesBack() {
        let anchor = CGPoint(x: 0.25, y: 0.5)
        let rest = scene(after: nil).position(anchor: anchor, phase: 0)
        // The poke lands 40 points to the doodle's left.
        let offset = CGSize(width: rest.x - 40 - center.x, height: 0)
        let pushed = scene(pokedAt: offset, after: 0.15).position(anchor: anchor, phase: 0)
        let unpushed = scene(after: 0.15).position(anchor: anchor, phase: 0)
        #expect(pushed.x - unpushed.x > 8)
        let settled = scene(pokedAt: offset, after: WelcomePoke.lifetime).position(anchor: anchor, phase: 0)
        let unpushedLater = scene(after: WelcomePoke.lifetime).position(anchor: anchor, phase: 0)
        #expect(abs(settled.x - unpushedLater.x) < 0.01)
    }

    @Test func theDoodlesDriftOnlyALittleFromTheirPlaces() {
        let rest = scene(after: nil).position(anchor: CGPoint(x: 0.25, y: 0.1), phase: 1.7)
        for elapsed in stride(from: 0.0, to: 30, by: 1.3) {
            let drifted = scene(after: elapsed).position(anchor: CGPoint(x: 0.25, y: 0.1), phase: 1.7)
            #expect(hypot(drifted.x - rest.x, drifted.y - rest.y) < 7)
        }
    }

    @Test func aRightToLeftLanguageMirrorsTheDoodles() {
        let mirrored = scene(after: nil, rightToLeft: true).position(anchor: CGPoint(x: 0.25, y: 0.1), phase: 0)
        #expect(mirrored == CGPoint(x: 301.5, y: 35))
    }

    @Test func onAWideScreenTheDoodlesKeepAroundTheEnvelopes() {
        let wide = WelcomeScene(size: CGSize(width: 1000, height: 400), pokes: [], clock: .stopped, rightToLeft: false)
        #expect(wide.position(anchor: CGPoint(x: 0, y: 0.5), phase: 0) == CGPoint(x: 200, y: 200))
        #expect(wide.position(anchor: CGPoint(x: 1, y: 0.5), phase: 0) == CGPoint(x: 800, y: 200))
    }

    // MARK: Dragging the envelopes

    @Test func envelopesLeftAloneDoNotLean() {
        let lean = WelcomeLean(pull: .zero)
        #expect(lean.shift == .zero)
        #expect(lean.pitch == 0)
        #expect(lean.yaw == 0)
        #expect(lean.spread == 0)
    }

    @Test func theEnvelopesFollowAFingerHalfTheWayAtFirst() {
        let lean = WelcomeLean(pull: CGSize(width: 10, height: -6))
        #expect(abs(lean.shift.width - 5) < 0.1)
        #expect(abs(lean.shift.height + 3) < 0.1)
        // They tip over with the drag, and the fan starts to open.
        #expect(lean.yaw > 0)
        #expect(lean.pitch > 0)
        #expect(lean.spread > 0)
    }

    @Test func howeverFarTheFingerGoesTheEnvelopesStayWithinReach() {
        let lean = WelcomeLean(pull: CGSize(width: 4000, height: -4000))
        #expect(lean.shift.width <= WelcomeLean.reach)
        #expect(lean.shift.height >= -WelcomeLean.reach)
        #expect(lean.yaw <= 22)
        #expect(lean.pitch <= 22)
        #expect(lean.spread == 0.5)
    }
}
