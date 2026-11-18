import CoreGraphics
import Foundation
import Testing

@testable import MailUI

/// The paper plane game's way in and way out, and the ring of doodles behind it. The game's first frame is what the
/// Inbox Zero scene drew at the tenth tap and its last is the scene at rest, so the morphs are seamless.
@MainActor struct PlaneGameMorphTests {
    /// A moment between two of the planes that pass by themselves.
    private let tapped = Date(timeIntervalSinceReferenceDate: 57_142_857 * DoodleScene.passEvery + 6)
    private let screen = CGSize(width: 402, height: 874)
    private let band: ClosedRange<CGFloat> = 120...820

    private func stage(layout: InboxZeroLayout = .full) -> InboxZeroStage {
        InboxZeroStage(field: CGRect(x: 0, y: 140, width: 402, height: 520), layout: layout, pileWidth: 200)
    }

    private func scene(rightToLeft: Bool = false, energy: Double = 1) -> DoodleScene {
        let stage = stage()
        return DoodleScene(
            size: stage.field.size, pokes: [DoodlePoke(offset: .zero, time: tapped - 0.4, number: 0)],
            clock: .running(tapped), rightToLeft: rightToLeft, focus: stage.focus, energy: energy)
    }

    // MARK: The door

    @Test(arguments: [
        (CGPoint(x: 201, y: 166), true),
        (CGPoint(x: 102, y: 97), true),
        (CGPoint(x: 300, y: 166), true),
        (CGPoint(x: 302, y: 166), false),
        (CGPoint(x: 201, y: 90), false),
        (CGPoint(x: 201, y: 300), false),
    ])
    func onlyTapsOnTheEnvelopesCount(location: CGPoint, counts: Bool) {
        // The envelopes are 200 wide and 140 tall, centered 96 + 70 down the field.
        #expect(stage().pile.contains(location) == counts)
    }

    @Test func theStageMovesIntoTheWindowWithItsField() {
        let moved = stage().converted { $0.offsetBy(dx: 10, dy: 50) }
        let expected = CGPoint(x: 211, y: 140 + 50 + 166)
        #expect(moved.center == expected)
        #expect(moved.focus == stage().focus)
    }

    // MARK: Takeoff

    @Test func theTakeoffStartsWithTheScenesEnvelopesAndNoPaper() throws {
        let scene = scene()
        let first = PlaneGameTakeoff(elapsed: 0, reduceMotion: false)
        let pile = try #require(first.pile(from: scene))
        #expect(pile.fan == scene.fan)
        #expect(pile.lift == scene.lift)
        #expect(pile.scale == 1)
        #expect(pile.width == 1)
        #expect(first.paper == 0)
        #expect(first.planeWidth == 0)
        #expect(first.hud == 0)
    }

    @Test func theEnvelopesSquareUpShrinkAndBecomeThePlane() throws {
        let scene = scene()
        let squared = try #require(PlaneGameTakeoff(elapsed: 0.25, reduceMotion: false).pile(from: scene))
        #expect(squared.fan == 0)
        #expect(squared.lift == 0)
        let shrunk = try #require(PlaneGameTakeoff(elapsed: 0.40, reduceMotion: false).pile(from: scene))
        #expect(abs(shrunk.scale - PlaneGameTakeoff.foldedSize) < 0.001)
        #expect(shrunk.width < 0.5)
        #expect(PlaneGameTakeoff(elapsed: PlaneGameTakeoff.planeSetsOff, reduceMotion: false).pile(from: scene) == nil)
        let widths = stride(from: 0.42, through: 0.7, by: 0.01).map {
            PlaneGameTakeoff(elapsed: $0, reduceMotion: false).planeWidth
        }
        #expect(widths.max() ?? 0 > 1)
        #expect(widths.last == 1)
    }

    @Test func theTakeoffEndsOnPaperWithTheHUD() {
        let done = PlaneGameTakeoff(elapsed: PlaneGameTakeoff.duration, reduceMotion: false)
        #expect(done.isDone)
        #expect(done.paper == 1)
        #expect(done.hud == 1)
        #expect(done.planeWidth == 1)
    }

    @Test func withReduceMotionTheTakeoffIsACrossFade() throws {
        let scene = scene()
        let first = try #require(PlaneGameTakeoff(elapsed: 0, reduceMotion: true).pile(from: scene))
        #expect(first.opacity == 1)
        #expect(first.width == 1)
        let half = PlaneGameTakeoff(elapsed: 0.15, reduceMotion: true)
        #expect(abs(half.paper - 0.5) < 0.001)
        #expect(half.planeWidth == 1)
        #expect(half.planeOpacity == half.paper)
        #expect(PlaneGameTakeoff(elapsed: PlaneGameTakeoff.crossFade, reduceMotion: true).pile(from: scene) == nil)
    }

    @Test func aRingThatWasntDrawnFadesInWithThePaper() {
        let takeoff = PlaneGameTakeoff(elapsed: 0.2, reduceMotion: false)
        #expect(takeoff.backdrop(decorated: true) == 1)
        #expect(takeoff.backdrop(decorated: false) == takeoff.paper)
    }

    @Test(arguments: [false, true])
    func theRingsPaperPlaneLeavesWithThePaper(reduceMotion: Bool) {
        #expect(PlaneGameTakeoff(elapsed: 0, reduceMotion: reduceMotion).planeDoodle == 1)
        #expect(PlaneGameTakeoff(elapsed: 0.40, reduceMotion: reduceMotion).planeDoodle == 0)
        #expect(PlaneGameTakeoff(elapsed: PlaneGameTakeoff.duration, reduceMotion: reduceMotion).planeDoodle == 0)
    }

    @Test func theRingsPaperPlaneComesHomeWithTheRing() {
        let landing = { PlaneGameLanding(elapsed: $0, reduceMotion: false) }
        #expect(landing(0).planeDoodle == 0)
        let halfway = stride(from: 0.0, through: 1.9, by: 0.01).first { landing($0).ringReturn >= 0.5 } ?? 0
        #expect(landing(halfway - 0.01).planeDoodle == 0)
        let fading = stride(from: halfway, through: 1.9, by: 0.01).map { landing($0).planeDoodle }
        #expect(fading == fading.sorted())
        #expect(landing(PlaneGameLanding.duration).planeDoodle == 1)
    }

    // MARK: Landing

    @Test(arguments: [false, true])
    func theLandingEndsOnTheScenesRestPose(reduceMotion: Bool) {
        let last = PlaneGameLanding(
            elapsed: PlaneGameLanding(elapsed: 0, reduceMotion: reduceMotion).length, reduceMotion: reduceMotion)
        #expect(last.pile == .rest)
        #expect(last.paper == 0)
        #expect(last.play == 0)
        #expect(last.ringReturn == 1)
        #expect(last.planeDoodle == 1)
    }

    @Test func theEnvelopesOpenFromThePlanesLineAndSpringBack() throws {
        #expect(PlaneGameLanding(elapsed: 0.8, reduceMotion: false).pile == nil)
        // The plane narrows all the way to a line, which the envelopes open from.
        let squeezing = (0...12).map {
            PlaneGameLanding(elapsed: PlaneGameLanding.planeArrives + Double($0) * 0.01, reduceMotion: false).planeWidth
        }
        #expect(squeezing == squeezing.sorted(by: >))
        #expect(PlaneGameLanding(elapsed: PlaneGameLanding.pileOpens, reduceMotion: false).planeWidth == 0)
        let opening = try #require(PlaneGameLanding(elapsed: PlaneGameLanding.pileOpens, reduceMotion: false).pile)
        #expect(opening.width == 0)
        #expect(abs(opening.scale - PlaneGameTakeoff.foldedSize) < 0.001)
        #expect(opening.fan == 0)
        let fans = stride(from: 0.95, to: 1.9, by: 0.01).compactMap {
            PlaneGameLanding(elapsed: $0, reduceMotion: false).pile?.fan
        }
        #expect(fans.max() ?? 0 > 1.05)
    }

    @Test func thePaperStaysUntilTheEnvelopesAreBack() {
        #expect(PlaneGameLanding(elapsed: 0.85, reduceMotion: false).paper == 1)
        #expect(PlaneGameLanding(elapsed: 1.35, reduceMotion: false).paper == 0)
        #expect(PlaneGameLanding(elapsed: 0.3, reduceMotion: false).play == 0)
    }

    @Test func flyingOffFadesThePaperInAMoment() {
        #expect(PlaneGameFlyOff(elapsed: 0).paper == 1)
        #expect(PlaneGameFlyOff(elapsed: PlaneGameFlyOff.duration).paper == 0)
        #expect(PlaneGameFlyOff(elapsed: 0.2).planeShift > 0)
    }

    // MARK: Backdrop

    private func backdrop(
        decorated: Bool = true, rightToLeft: Bool = false, reduceMotion: Bool = false
    ) -> PlaneGameBackdrop {
        let stage = stage(layout: decorated ? .full : .bare)
        return PlaneGameBackdrop(
            doodles: Doodle.inboxZero, handoff: InboxZeroHandoff(scene: scene(rightToLeft: rightToLeft), stage: stage),
            screen: screen, band: band,
            reduceMotion: reduceMotion)
    }

    @Test(arguments: [false, true])
    func atDistanceZeroTheBackdropIsTheRingAsTheSceneDrewIt(rightToLeft: Bool) {
        let scene = scene(rightToLeft: rightToLeft)
        let origin = stage().field.origin
        let drawn = Doodle.inboxZero.enumerated().map { index, doodle in
            let pose = scene.pose(of: doodle, at: index)
            return DoodlePose(
                position: CGPoint(x: pose.position.x + origin.x, y: pose.position.y + origin.y), angle: pose.angle)
        }
        #expect(backdrop(rightToLeft: rightToLeft).poses(at: 0) == drawn)
    }

    @Test(arguments: [false, true])
    func theRingDriftsTowardTheLeadingEdge(rightToLeft: Bool) {
        let backdrop = backdrop(rightToLeft: rightToLeft)
        for (start, later) in zip(backdrop.poses(at: 0), backdrop.poses(at: 40)) {
            let moved = later.position.x - start.position.x
            #expect(rightToLeft ? moved > 0 : moved < 0)
        }
    }

    @Test func eachDoodleDriftsAtItsOwnDepth() {
        let depths = (0..<12).map(PlaneGameBackdrop.depth(of:))
        #expect(Set(depths).count == 12)
        #expect(depths.min() == 0.35)
        #expect(depths.max() == 0.6)
    }

    @Test(arguments: [false, true])
    func doodlesComeRoundAgainInsideTheBandAndOffScreen(rightToLeft: Bool) {
        let backdrop = backdrop(rightToLeft: rightToLeft)
        for distance in stride(from: CGFloat(2000), through: 20000, by: 997) {
            for pose in backdrop.poses(at: distance) {
                #expect(band.contains(pose.position.y))
                #expect(pose.position.x >= -PlaneGameBackdrop.margin)
                #expect(pose.position.x <= screen.width + PlaneGameBackdrop.margin)
            }
        }
    }

    @Test func aDoodleComesRoundAtANewHeightEachLap() {
        let backdrop = backdrop()
        let heights = stride(from: CGFloat(3000), through: 30000, by: 3000).map { backdrop.poses(at: $0)[0].position.y }
        #expect(Set(heights).count > 3)
    }

    @Test func withReduceMotionTheRingHoldsStill() {
        let backdrop = backdrop(reduceMotion: true)
        #expect(backdrop.poses(at: 5000) == backdrop.poses(at: 0))
    }

    @Test func theRingFliesHomeToTheScenesRestPoses() {
        let backdrop = backdrop()
        let rest = PlaneGameBackdrop.rest(of: Doodle.inboxZero, on: stage(), rightToLeft: false)
        #expect(backdrop.poses(at: 3000, returning: 1, to: rest) == rest)
        #expect(backdrop.poses(at: 3000, returning: 0, to: rest) == backdrop.poses(at: 3000))
        let resting = DoodleScene(
            size: stage().field.size, pokes: [], clock: .running(tapped), rightToLeft: false, focus: stage().focus,
            energy: 0)
        let origin = stage().field.origin
        for (index, doodle) in Doodle.inboxZero.enumerated() {
            let pose = resting.pose(of: doodle, at: index)
            let onScreen = CGPoint(x: pose.position.x + origin.x, y: pose.position.y + origin.y)
            #expect(rest[index].position == onScreen)
            #expect(rest[index].angle == doodle.angle)
        }
    }

    // MARK: Windows that change size

    /// How far `pose` is from the leading edge of a screen `width` wide.
    private func fromLeading(_ pose: DoodlePose, width: CGFloat, rightToLeft: Bool) -> CGFloat {
        rightToLeft ? width - pose.position.x : pose.position.x
    }

    @Test(arguments: [false, true], [CGFloat(300), 1000])
    func aResizeKeepsEveryDoodleWhereItWasFromTheLeadingEdge(rightToLeft: Bool, width: CGFloat) {
        var backdrop = backdrop(rightToLeft: rightToLeft)
        // Far enough that some doodles have come round again.
        let distance: CGFloat = 1800
        let before = backdrop.poses(at: distance)
        backdrop.fit(mirror: PlaneGameMirror(width: width, rightToLeft: rightToLeft), band: 200...600, at: distance)
        let after = backdrop.poses(at: distance)
        for (old, new) in zip(before, after) {
            let kept = fromLeading(old, width: screen.width, rightToLeft: rightToLeft)
            #expect(abs(fromLeading(new, width: width, rightToLeft: rightToLeft) - kept) < 0.001)
            #expect(new.position.y == old.position.y)
            #expect(new.angle == old.angle)
        }
    }

    @Test(arguments: [false, true], [CGFloat(300), 1000])
    func afterAResizeEachDoodleDriftsOnFromWhereItWas(rightToLeft: Bool, width: CGFloat) {
        var backdrop = backdrop(rightToLeft: rightToLeft)
        let distance: CGFloat = 1800
        backdrop.fit(mirror: PlaneGameMirror(width: width, rightToLeft: rightToLeft), band: 200...600, at: distance)
        let extra: CGFloat = 12
        let start = backdrop.poses(at: distance)
        let later = backdrop.poses(at: distance + extra)
        for (index, (from, to)) in zip(start, later).enumerated() {
            let along = fromLeading(from, width: width, rightToLeft: rightToLeft)
            // One that goes past the leading edge in the extra comes round instead.
            guard along - PlaneGameBackdrop.depth(of: index) * extra >= -PlaneGameBackdrop.margin else { continue }
            let drifted = along - fromLeading(to, width: width, rightToLeft: rightToLeft)
            #expect(abs(drifted - PlaneGameBackdrop.depth(of: index) * extra) < 0.001)
            #expect(to.position.y == from.position.y)
        }
    }

    @Test(arguments: [false, true], [CGFloat(300), 1000])
    func afterAResizeDoodlesComeRoundInsideTheNewBandAndWidth(rightToLeft: Bool, width: CGFloat) {
        var backdrop = backdrop(rightToLeft: rightToLeft)
        let band: ClosedRange<CGFloat> = 200...600
        backdrop.fit(mirror: PlaneGameMirror(width: width, rightToLeft: rightToLeft), band: band, at: 1800)
        // Past the farthest a doodle can have been, so every one has come round since the resize.
        for distance in stride(from: CGFloat(1800 + 2 * (1000 + 900) / 0.35), through: 40000, by: 997) {
            for pose in backdrop.poses(at: distance) {
                #expect(band.contains(pose.position.y))
                #expect(pose.position.x >= -PlaneGameBackdrop.margin)
                #expect(pose.position.x <= width + PlaneGameBackdrop.margin)
            }
        }
    }
}
