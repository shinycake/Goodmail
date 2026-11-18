import CoreGraphics
import Foundation
import PlaneGame
import SwiftUI
import Testing
import UIKit

@testable import MailUI

/// The game screen's model: the phase it is in, the clock that steps it, the way out and the mail that arrives
/// during a game. The tests drive the clock themselves, with no display.
@MainActor
struct PlaneGameModelTests {
    /// The list the game came from, as the tests set it.
    private final class List {
        var stage: InboxZeroStage? = InboxZeroStage(
            field: CGRect(x: 0, y: 140, width: 402, height: 520), layout: .full, pileWidth: 200)
        var threads = 0
    }

    private let list = List()
    private let defaults = UserDefaults(suiteName: "PlaneGameModelTests.\(UUID().uuidString)")!

    /// When the tenth tap landed.
    private let tapped = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// A game started from a scene with `pokes` in the air, on an iPhone held upright unless `screen` says otherwise.
    private func model(
        reduceMotion: Bool = false, pokes: [DoodlePoke] = [], rightToLeft: Bool = false,
        screen: CGSize = CGSize(width: 402, height: 874),
        safeArea: UIEdgeInsets = UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0)
    ) throws -> PlaneGameModel {
        let stage = try #require(list.stage)
        let scene = DoodleScene(
            size: stage.field.size, pokes: pokes, clock: .running(tapped), rightToLeft: rightToLeft,
            focus: stage.focus)
        // The planes in the air fly in the window's sky, which hands them over as they were at the tenth tap.
        let window = CGRect(origin: .zero, size: screen)
        let sky = InboxZeroSkyHandoff(
            scene: DoodleScene(
                sky: window, stage: stage, pokes: pokes, wake: .awake(since: tapped, rampFrom: nil),
                clock: .running(tapped), rightToLeft: rightToLeft),
            frame: window)
        return PlaneGameModel(
            handoff: InboxZeroHandoff(scene: scene, stage: stage, sky: sky), screen: screen, safeArea: safeArea,
            reduceMotion: reduceMotion,
            list: PlaneGameList(stage: { [list] in list.stage }, threads: { [list] in list.threads }),
            defaults: defaults, seed: 1)
    }

    private func run(_ model: PlaneGameModel, for seconds: TimeInterval) {
        for _ in 0..<Int((seconds * 60).rounded(.up)) { model.tick(by: 1.0 / 60) }
    }

    // MARK: The clock

    @Test func theGameOpensWithTheTakeoff() throws {
        let model = try model()
        #expect(model.phase == .flying(.takeoff))
        #expect(model.clock == 0)
        #expect(model.look.paper == 0)
    }

    @Test func aLongStepIsCappedSoNothingTeleports() throws {
        let model = try model()
        model.tick(by: 2)
        #expect(model.clock == PlaneGameModel.longestStep)
    }

    @Test func thePlaneFoldsOutOfTheEnvelopesOrIsInPlaceWithReduceMotion() throws {
        let center = try #require(list.stage).center
        #expect(try model().world.plane.position == center)
        let reduced = try model(reduceMotion: true)
        #expect(reduced.world.plane.position == reduced.world.field.startingPlace)
    }

    @Test func thePlaneFliesNearTheBottomClearOfTheHUDTheSidesAndTheHomeIndicator() {
        let field = PlaneGameModel.field(
            screen: CGSize(width: 402, height: 874), safeArea: UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0))
        #expect(field.lanes == 12...390)
        #expect(field.ceiling == 126)
        #expect(field.row == 720)
        #expect(field.startingPlace == CGPoint(x: 201, y: 720))
    }

    @Test func afterTheTakeoffThePlaneIsInTheMiddleOfTheLanesOnTheRowPointingUp() throws {
        let model = try model()
        run(model, for: PlaneGameTakeoff.duration)
        #expect(model.world.plane.status == .flying)
        #expect(model.world.plane.position == model.world.field.startingPlace)
        #expect(model.world.plane.heading == 0)
    }

    @Test(arguments: [false, true])
    func aDragSlidesThePlaneSidewaysOnlyTheSameWayInEveryLanguage(rightToLeft: Bool) throws {
        let model = try model(rightToLeft: rightToLeft)
        run(model, for: PlaneGameTakeoff.duration + 0.1)
        let before = model.world.plane.position
        model.touch(sideways: 0)
        model.touch(sideways: 30)
        model.tick(by: 1.0 / 60)
        #expect(abs(model.world.plane.position.x - (before.x + 30)) < 0.0001)
        #expect(model.world.plane.position.y == before.y)
        model.touch(sideways: 10)
        model.tick(by: 1.0 / 60)
        #expect(abs(model.world.plane.position.x - (before.x + 10)) < 0.0001)
    }

    /// The opacity of the ring's paper plane doodles and of the rest of the ring, in what the screen draws now.
    private func ring(_ model: PlaneGameModel) -> (planes: Set<Double>, others: Set<Double>) {
        let doodles = zip(Doodle.inboxZero, model.look.canvas.backdrop)
        return (
            Set(doodles.filter { $0.0.shape == .plane }.map(\.1.opacity)),
            Set(doodles.filter { $0.0.shape != .plane }.map(\.1.opacity))
        )
    }

    @Test func theRingsPaperPlaneStaysOutOfPlay() throws {
        #expect(Doodle.inboxZero.contains { $0.shape == .plane })
        let model = try model()
        #expect(ring(model).planes == [1])
        run(model, for: 0.41)
        #expect(ring(model).planes == [0])
        #expect(ring(model).others == [1])
        run(model, for: 5)
        #expect(ring(model).planes == [0])
        model.exit()
        run(model, for: PlaneGameLanding.duration - 1.0 / 60)
        #expect(ring(model).planes == [1])
        #expect(ring(model).others == [1])
    }

    @Test func theScenesPlanesFadeWithThePaper() throws {
        let model = try model(pokes: [DoodlePoke(offset: .zero, time: tapped - 0.2, number: 0)])
        #expect(model.look.flights?.opacity == 1)
        run(model, for: 0.2)
        let fading = try #require(model.look.flights?.opacity)
        #expect(fading > 0 && fading < 1)
        #expect(abs(fading - (1 - model.look.paper)) < 0.0001)
        run(model, for: 0.21)
        #expect(model.look.flights == nil)
    }

    @Test(arguments: [-2000, 2000] as [CGFloat])
    func inLandscapeThePlaneKeepsClearOfTheSideSafeAreas(sideways: CGFloat) throws {
        let model = try model(
            screen: CGSize(width: 874, height: 402), safeArea: UIEdgeInsets(top: 0, left: 62, bottom: 21, right: 62))
        run(model, for: PlaneGameTakeoff.duration + 0.1)
        model.touch(sideways: 0)
        model.touch(sideways: sideways)
        model.tick(by: 1.0 / 60)
        let x = model.world.plane.position.x
        #expect(x >= 62 + 12 + PlaneGameRules.planeRadius)
        #expect(x <= 874 - 62 - 12 - PlaneGameRules.planeRadius)
        #expect(model.world.plane.position.y == model.world.field.row)
    }

    // MARK: The way out

    @Test func theTakeoffPlaysOutBeforeTheWayOut() throws {
        let model = try model()
        run(model, for: 0.5)
        model.exit()
        #expect(model.phase == .flying(.takeoff))
    }

    @Test func leavingFoldsBackIntoTheEnvelopesAndThenTheGameIsGone() throws {
        let model = try model()
        run(model, for: PlaneGameTakeoff.duration + 0.1)
        model.exit()
        guard case .leaving(let leaving) = model.phase, case .home(let stage, let path) = leaving.way else {
            Issue.record("Expected to fold back home, got \(model.phase)")
            return
        }
        #expect(stage == list.stage)
        #expect(path == .landing(from: model.world.plane.position, to: stage.center))
        model.exit()
        #expect(model.phase == .leaving(leaving))
        run(model, for: PlaneGameLanding.duration - 0.1)
        #expect(model.phase == .leaving(leaving))
        run(model, for: 0.2)
        #expect(model.phase == .gone)
    }

    @Test func leavingWhenTheInboxHasMailFliesOff() throws {
        let model = try model()
        run(model, for: PlaneGameTakeoff.duration + 0.1)
        list.stage = nil
        model.exit()
        guard case .leaving(let leaving) = model.phase else {
            Issue.record("Expected to leave, got \(model.phase)")
            return
        }
        #expect(leaving.way == .away)
        run(model, for: PlaneGameFlyOff.duration + 0.05)
        #expect(model.phase == .gone)
    }

    @Test(arguments: [
        PlaneGameLeaving.Way.away,
        .home(
            InboxZeroStage(field: CGRect(x: 0, y: 140, width: 402, height: 520), layout: .full, pileWidth: 200),
            path: .landing(from: CGPoint(x: 201, y: 720), to: CGPoint(x: 201, y: 306))),
    ])
    func theCardFadesWithWhatWasInPlayOnTheWayOut(way: PlaneGameLeaving.Way) {
        let result = PlaneGameResult(score: 40, best: 90, isNewBest: false)
        #expect(
            PlaneGamePhase.over(result).card(at: 7, reduceMotion: false) == PlaneGameCard(result: result, opacity: 1))
        let leaving = PlaneGamePhase.leaving(PlaneGameLeaving(since: 10, way: way, ending: result))
        let opacities = stride(from: 10.0, through: 10.5, by: 0.05).compactMap {
            leaving.card(at: $0, reduceMotion: false)?.opacity
        }
        #expect(opacities.count == 11)
        #expect(opacities.first == 1)
        #expect(opacities.last == 0)
        #expect(opacities == opacities.sorted(by: >))
        let midGame = PlaneGamePhase.leaving(PlaneGameLeaving(since: 10, way: way, ending: nil))
        #expect(midGame.card(at: 10, reduceMotion: false) == nil)
    }

    @Test func playAgainOnlyFollowsAGameOver() throws {
        let model = try model()
        run(model, for: 1)
        model.playAgain()
        #expect(model.phase == .flying(.takeoff))
    }

    @Test func playAgainSendsANewPlaneStraightUpFromBelowTheBottomEdge() throws {
        let model = try model()
        bring(model, to: .over)
        try #require(model.phase.isOverForTests)
        model.playAgain()
        #expect(model.phase == .flying(.again))
        let field = model.world.field
        #expect(model.world.plane.position == CGPoint(x: field.startingPlace.x, y: 874 + PlaneGameRules.belowField))
        run(model, for: FlightPath.duration + 0.05)
        #expect(model.world.plane.status == .flying)
        #expect(model.world.plane.position == field.startingPlace)
    }

    @Test func afterAGameOverThePlaneThatLandsComesUpFromBelowTheBottomEdge() throws {
        let model = try model()
        bring(model, to: .over)
        try #require(model.phase.isOverForTests)
        model.exit()
        guard case .leaving(let leaving) = model.phase, case .home(let stage, let path) = leaving.way else {
            Issue.record("Expected to fold back home, got \(model.phase)")
            return
        }
        #expect(path.start == CGPoint(x: stage.center.x, y: 874 + PlaneGameRules.belowField))
        #expect(path.end == stage.center)
    }

    @Test func theStatusBarStepsBackOnlyWhileThePaperCoversTheWindow() throws {
        let model = try model()
        #expect(!model.coversWindow)
        run(model, for: 0.5)
        #expect(model.coversWindow)
        run(model, for: 1)
        model.exit()
        #expect(!model.coversWindow)
    }

    // MARK: The hint

    @Test func theHintGoesOnceThePlaneIsSteered() throws {
        let model = try model()
        run(model, for: PlaneGameTakeoff.duration + 0.1)
        #expect(model.hint == 1)
        model.touch(sideways: 0)
        model.touch(sideways: 12)
        model.release()
        run(model, for: 0.4)
        #expect(model.hint == 0)
    }

    @Test func aFingerThatHasntMovedSidewaysLeavesTheHint() throws {
        let model = try model()
        run(model, for: PlaneGameTakeoff.duration + 0.1)
        model.touch(sideways: 0)
        model.touch(sideways: 0)
        model.release()
        run(model, for: 0.4)
        #expect(model.hint == 1)
    }

    @Test(arguments: [false, true])
    func theHintSitsAcrossTheMiddleBetweenTheHUDAndThePlane(landscape: Bool) throws {
        let screen = landscape ? CGSize(width: 874, height: 402) : CGSize(width: 402, height: 874)
        let model = try model(
            screen: screen,
            safeArea: landscape
                ? UIEdgeInsets(top: 0, left: 62, bottom: 21, right: 62)
                : UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0))
        let field = model.world.field
        #expect(model.hintCenter == CGPoint(x: screen.width / 2, y: screen.height * 0.6))
        #expect(model.hintCenter.y > field.ceiling)
        // Clear of the plane and its own height.
        #expect(model.hintCenter.y < field.row - 2 * PlaneGameRules.planeRadius - 20)
    }

    @Test func theHintGoesByItselfAfterAWhile() throws {
        let model = try model()
        run(model, for: PlaneGameTakeoff.duration + PlaneGameModel.hintStays + 0.4)
        #expect(model.hint == 0)
    }

    // MARK: New mail

    @Test func mailThatArrivesDuringTheGameIsCounted() throws {
        let model = try model()
        run(model, for: 0.1)
        #expect(model.mailWaiting == 0)
        #expect(model.mailArrivals == 0)
        list.threads = 1
        model.tick(by: 1.0 / 60)
        #expect(model.mailWaiting == 1)
        #expect(model.mailArrivals == 1)
        list.threads = 3
        model.tick(by: 1.0 / 60)
        #expect(model.mailWaiting == 3)
        #expect(model.mailArrivals == 2)
    }

    @Test func mailThatGoesAwayIsNoArrival() throws {
        let model = try model()
        list.threads = 2
        model.tick(by: 1.0 / 60)
        list.threads = 1
        model.tick(by: 1.0 / 60)
        #expect(model.mailWaiting == 1)
        #expect(model.mailArrivals == 1)
        list.threads = 0
        model.tick(by: 1.0 / 60)
        #expect(model.mailWaiting == 0)
        #expect(model.mailArrivals == 1)
        run(model, for: 0.5)
        #expect(model.mailArrivals == 1)
    }

    // MARK: Best score

    @Test func onlyABetterScoreBecomesTheBest() {
        #expect(PlaneGameBest.record(0, in: defaults) == PlaneGameResult(score: 0, best: 0, isNewBest: false))
        #expect(PlaneGameBest.record(120, in: defaults) == PlaneGameResult(score: 120, best: 120, isNewBest: true))
        #expect(PlaneGameBest.record(80, in: defaults) == PlaneGameResult(score: 80, best: 120, isNewBest: false))
        #expect(defaults.integer(forKey: PlaneGameBest.key) == 120)
    }

    // MARK: Windows that change size

    /// Where the Inbox lays its envelopes out after the window changes size under the landing.
    private let movedStage = InboxZeroStage(
        field: CGRect(x: 320, y: 90, width: 500, height: 600), layout: .full, pileWidth: 220)

    @Test func theLandingFollowsTheEnvelopesWhenTheInboxLaysOutAgain() throws {
        let model = try model()
        run(model, for: PlaneGameTakeoff.duration + 0.1)
        model.exit()
        run(model, for: 0.3)
        list.stage = movedStage
        run(model, for: PlaneGameLanding.duration - 0.3 - 1.0 / 60)
        guard case .leaving(let leaving) = model.phase, case .home(let stage, let path) = leaving.way else {
            Issue.record("Expected to fold back home, got \(model.phase)")
            return
        }
        #expect(stage == movedStage)
        #expect(path.end == movedStage.center)
        let look = model.look
        #expect(look.pile?.center == movedStage.center)
        #expect(look.pile?.width == movedStage.pileWidth)
        let rest = PlaneGameBackdrop.rest(of: Doodle.inboxZero, on: movedStage, rightToLeft: false)
        #expect(look.canvas.backdrop.map(\.pose) == rest)
        run(model, for: 2.0 / 60)
        #expect(model.phase == .gone)
    }

    @Test func theLandingKeepsItsPlaceWhenTheSceneIsGoneMidway() throws {
        let model = try model()
        run(model, for: PlaneGameTakeoff.duration + 0.1)
        model.exit()
        run(model, for: 0.3)
        let landing = model.phase
        list.stage = nil
        run(model, for: 0.5)
        #expect(model.phase == landing)
    }

    /// A field that is a window's whole size, safe areas and all, from the smallest the system allows to a 13 inch
    /// iPad's.
    private static let windows: [(CGSize, UIEdgeInsets)] = [
        CGSize(width: 200, height: 150), CGSize(width: 320, height: 480), CGSize(width: 402, height: 874),
        CGSize(width: 874, height: 402), CGSize(width: 1366, height: 1024), CGSize(width: 1024, height: 1366),
        CGSize(width: 507, height: 1180), CGSize(width: 1180, height: 820),
    ].flatMap { size in
        [(size, UIEdgeInsets.zero), (size, UIEdgeInsets(top: 62, left: 62, bottom: 34, right: 62))]
    }

    enum Moment: CaseIterable, Sendable {
        case takeoff, play, over, landing, flyingOff
    }

    /// `model` brought to `moment`.
    private func bring(_ model: PlaneGameModel, to moment: Moment) {
        switch moment {
        case .takeoff:
            run(model, for: 0.3)
        case .play:
            run(model, for: PlaneGameTakeoff.duration + 2)
        case .over:
            for _ in 0..<(60 * 600) where !model.phase.isOverForTests { model.tick(by: 1.0 / 60) }
        case .landing:
            run(model, for: PlaneGameTakeoff.duration + 0.1)
            model.exit()
        case .flyingOff:
            run(model, for: PlaneGameTakeoff.duration + 0.1)
            list.stage = nil
            model.exit()
        }
    }

    @Test(arguments: Moment.allCases)
    func resizingAnyWayNeverBreaksTheGame(at moment: Moment) throws {
        let model = try model()
        bring(model, to: moment)
        if moment == .over { try #require(model.phase.isOverForTests) }
        for (screen, safeArea) in Self.windows + Self.windows.reversed() {
            model.resize(screen: screen, safeArea: safeArea)
            for _ in 0..<3 {
                model.tick(by: 1.0 / 60)
                let look = model.look
                let points =
                    look.canvas.backdrop.map(\.pose.position) + (look.canvas.plane.map { [$0.position] } ?? [])
                    + (look.pile.map { [$0.center] } ?? [])
                #expect(points.allSatisfy { $0.x.isFinite && $0.y.isFinite })
                #expect(look.paper.isFinite && look.hud.isFinite)
                let field = model.world.field
                let plane = model.world.plane
                switch plane.status {
                case .flying, .shaken:
                    #expect(field.lanes.contains(plane.position.x))
                    #expect(plane.position.y == field.row)
                case .launching, .down:
                    break
                }
            }
        }
    }
}

extension PlaneGamePhase {
    fileprivate var isOverForTests: Bool {
        if case .over = self { true } else { false }
    }
}
