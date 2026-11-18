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

    /// A game started from a scene with `pokes` in the air.
    private func model(reduceMotion: Bool = false, pokes: [DoodlePoke] = []) throws -> PlaneGameModel {
        let stage = try #require(list.stage)
        let scene = DoodleScene(
            size: stage.field.size, pokes: pokes, clock: .running(tapped), rightToLeft: false, focus: stage.focus)
        return PlaneGameModel(
            handoff: InboxZeroHandoff(scene: scene, stage: stage), screen: CGSize(width: 402, height: 874),
            safeArea: UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0), reduceMotion: reduceMotion,
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
        let field = try model(reduceMotion: true).world.field
        #expect(try model(reduceMotion: true).world.plane.position == PlaneGameModel.startingPlace(in: field))
    }

    @Test func theFieldKeepsClearOfTheHUDAndTheHomeIndicator() {
        let field = PlaneGameModel.field(
            screen: CGSize(width: 402, height: 874), safeArea: UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0),
            rightToLeft: false)
        let top: CGFloat = 62 + 64
        let bottom: CGFloat = 874 - 34 - 24
        #expect(field.band == top...bottom)
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

    @Test(arguments: [false, true])
    func inLandscapeThePlaneKeepsClearOfTheCameraOnItsLeadingSide(rightToLeft: Bool) {
        // Turned with the camera on the left.
        let field = PlaneGameModel.field(
            screen: CGSize(width: 874, height: 402), safeArea: UIEdgeInsets(top: 0, left: 62, bottom: 21, right: 62),
            rightToLeft: rightToLeft)
        #expect(field.leadingInset == 62)
        let leftOnly = PlaneGameModel.field(
            screen: CGSize(width: 874, height: 402), safeArea: UIEdgeInsets(top: 0, left: 62, bottom: 21, right: 0),
            rightToLeft: rightToLeft)
        #expect(leftOnly.leadingInset == (rightToLeft ? 0 : 62))
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
        #expect(path.end == stage.center)
        #expect(path.start == model.world.plane.position)
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
            path: LoopPath(from: .zero, to: CGPoint(x: 201, y: 306))),
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
        model.touch(CGSize(width: 0, height: 0))
        model.touch(CGSize(width: 0, height: 12))
        model.release()
        run(model, for: 0.4)
        #expect(model.hint == 0)
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
}
