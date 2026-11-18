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

    @Test func thePlaneOpensPointingUpAndTurnsOntoItsLaunchAsItOpens() {
        let turns = stride(from: 0.0, through: 1.3, by: 0.01).map {
            PlaneGameTakeoff(elapsed: $0, reduceMotion: false).planeTurn
        }
        #expect(PlaneGameTakeoff(elapsed: PlaneGameTakeoff.planeSetsOff, reduceMotion: false).planeTurn == 0)
        #expect(PlaneGameTakeoff(elapsed: 0.6, reduceMotion: false).planeTurn == 1)
        #expect(turns == turns.sorted())
        #expect(turns.last == 1)
        #expect(PlaneGameTakeoff(elapsed: 0, reduceMotion: true).planeTurn == 1)
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
        #expect(PlaneGameFlyOff(elapsed: 0.2).planeRise > 0)
    }

    // MARK: Backdrop

    private func backdrop(
        decorated: Bool = true, rightToLeft: Bool = false, reduceMotion: Bool = false
    ) -> PlaneGameBackdrop {
        let stage = stage(layout: decorated ? .full : .bare)
        return PlaneGameBackdrop(
            doodles: Doodle.inboxZero, handoff: InboxZeroHandoff(scene: scene(rightToLeft: rightToLeft), stage: stage),
            screen: screen, reduceMotion: reduceMotion)
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
    func theRingDriftsStraightDownInEveryLanguage(rightToLeft: Bool) {
        let backdrop = backdrop(rightToLeft: rightToLeft)
        for (index, (start, later)) in zip(backdrop.poses(at: 0), backdrop.poses(at: 40)).enumerated() {
            #expect(later.position.x == start.position.x)
            #expect(abs(later.position.y - start.position.y - PlaneGameBackdrop.depth(of: index) * 40) < 0.001)
            #expect(later.angle == start.angle)
        }
    }

    @Test func eachDoodleDriftsAtItsOwnDepth() {
        let depths = (0..<12).map(PlaneGameBackdrop.depth(of:))
        #expect(Set(depths).count == 12)
        #expect(depths.min() == 0.35)
        #expect(depths.max() == 0.6)
    }

    @Test(arguments: [false, true])
    func doodlesComeRoundAgainInsideTheWidthAndOffScreen(rightToLeft: Bool) {
        let backdrop = backdrop(rightToLeft: rightToLeft)
        for distance in stride(from: CGFloat(3000), through: 30000, by: 997) {
            for pose in backdrop.poses(at: distance) {
                #expect(pose.position.x >= 0 && pose.position.x <= screen.width)
                #expect(pose.position.y >= -PlaneGameBackdrop.margin)
                #expect(pose.position.y <= screen.height + PlaneGameBackdrop.margin)
            }
        }
    }

    @Test func aDoodleComesRoundFromAboveTheTop() {
        let backdrop = backdrop()
        // Just past the bottom margin, the first doodle is back at the top margin.
        let seed = backdrop.poses(at: 0)[0].position.y
        let wraps = (screen.height + PlaneGameBackdrop.margin - seed) / PlaneGameBackdrop.depth(of: 0)
        let comingRound = backdrop.poses(at: wraps + 1)[0]
        #expect(comingRound.position.y < -PlaneGameBackdrop.margin + 1)
        #expect(comingRound.angle == Doodle.inboxZero[0].angle)
    }

    @Test func aDoodleComesRoundAtANewXEachLap() {
        let backdrop = backdrop()
        let xs = stride(from: CGFloat(3000), through: 30000, by: 3000).map { backdrop.poses(at: $0)[0].position.x }
        #expect(Set(xs).count > 3)
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

    /// Sizes a window changes to: narrower and shorter, and wider and taller.
    private nonisolated static let resizes = [CGSize(width: 300, height: 400), CGSize(width: 1000, height: 1200)]

    @Test(arguments: resizes)
    func aResizeKeepsEveryDoodleWhereItWasOnTheScreen(size: CGSize) {
        var backdrop = backdrop()
        // Far enough that some doodles have come round again.
        let distance: CGFloat = 1800
        let before = backdrop.poses(at: distance)
        backdrop.fit(size: size, at: distance)
        #expect(backdrop.poses(at: distance) == before)
    }

    @Test(arguments: resizes)
    func afterAResizeEachDoodleDriftsOnFromWhereItWas(size: CGSize) {
        var backdrop = backdrop()
        let distance: CGFloat = 1800
        backdrop.fit(size: size, at: distance)
        let extra: CGFloat = 12
        let start = backdrop.poses(at: distance)
        let later = backdrop.poses(at: distance + extra)
        for (index, (from, to)) in zip(start, later).enumerated() {
            let fallen = from.position.y + PlaneGameBackdrop.depth(of: index) * extra
            // One that goes past the bottom edge in the extra comes round instead.
            guard fallen <= size.height + PlaneGameBackdrop.margin else { continue }
            #expect(abs(to.position.y - fallen) < 0.001)
            #expect(to.position.x == from.position.x)
        }
    }

    @Test(arguments: resizes)
    func afterAResizeDoodlesComeRoundInsideTheNewSize(size: CGSize) {
        var backdrop = backdrop()
        backdrop.fit(size: size, at: 1800)
        // Past the farthest a doodle can have to fall, so every one has come round since the resize.
        for distance in stride(from: CGFloat(1800 + 2 * (1200 + 900) / 0.35), through: 40000, by: 997) {
            for pose in backdrop.poses(at: distance) {
                #expect(pose.position.x >= 0 && pose.position.x <= size.width)
                #expect(pose.position.y >= -PlaneGameBackdrop.margin)
                #expect(pose.position.y <= size.height + PlaneGameBackdrop.margin)
            }
        }
    }
}
