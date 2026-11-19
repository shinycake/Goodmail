import CoreGraphics
import Foundation
import PlaneGame
import Testing
import UIKit

@testable import MailUI

/// Pausing the paper plane game: what can be paused, that nothing moves while it is, the countdown before it carries
/// on, the question before leaving it for new mail, and the ways on from each.
@MainActor
struct PlaneGamePauseTests {
    private let stage: InboxZeroStage? = InboxZeroStage(
        field: CGRect(x: 0, y: 140, width: 402, height: 520), layout: .full, pileWidth: 200)
    private let threads = Threads()
    private let defaults = UserDefaults(suiteName: "PlaneGamePauseTests.\(UUID().uuidString)")!

    /// How many threads the list shows, as a test sets it.
    private final class Threads {
        var count = 0
    }

    /// A game on an iPhone held upright, past its takeoff unless `takeoff` says otherwise.
    private func playing(takeoff: TimeInterval = PlaneGameTakeoff.duration + 2) throws -> PlaneGameModel {
        let stage = try #require(stage)
        let scene = DoodleScene(
            size: stage.field.size, pokes: [], clock: .running(.distantPast), rightToLeft: false, focus: stage.focus)
        let model = PlaneGameModel(
            handoff: InboxZeroHandoff(scene: scene, stage: stage), screen: CGSize(width: 402, height: 874),
            safeArea: UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0), reduceMotion: false,
            list: PlaneGameList(stage: { stage }, threads: { [threads] in threads.count }), defaults: defaults, seed: 1)
        run(model, for: takeoff)
        return model
    }

    private func run(_ model: PlaneGameModel, for seconds: TimeInterval) {
        for _ in 0..<Int((seconds * 60).rounded(.up)) { model.tick(by: 1.0 / 60) }
    }

    /// Picks Resume on the pause card and waits out the countdown, up to the frame the game carries on, which steps
    /// nothing yet.
    private func resume(_ model: PlaneGameModel) {
        model.resume()
        for _ in 0..<(60 * 4) where model.phase.isPaused { model.tick(by: 1.0 / 60) }
    }

    @Test func pausingHoldsTheWorldAndTheClockStill() throws {
        let model = try playing()
        model.touch(sideways: 0)
        model.pause()
        #expect(model.phase == .paused(.takeoff, .card))
        let clock = model.clock
        let world = model.world
        run(model, for: 5)
        #expect(model.clock == clock)
        #expect(model.world == world)
        #expect(model.coversWindow)
    }

    @Test func resumingCountsDownThreeSecondsThenCarriesOnWhereItStopped() throws {
        let model = try playing()
        model.pause()
        let distance = model.world.distance
        let clock = model.clock
        model.resume()
        #expect(model.phase == .paused(.takeoff, .countingDown(left: 3)))
        run(model, for: PlaneGameHold.countdown - 0.1)
        #expect(model.clock == clock)
        #expect(model.world.distance == distance)
        run(model, for: 0.2)
        #expect(model.phase == .flying(.takeoff))
        run(model, for: 0.5)
        #expect(model.world.distance > distance)
    }

    @Test func pausingDuringTheCountdownBringsTheCardBack() throws {
        let model = try playing()
        model.pause()
        model.resume()
        run(model, for: 1)
        #expect(model.canPause)
        model.pause()
        #expect(model.phase == .paused(.takeoff, .card))
        run(model, for: PlaneGameHold.countdown)
        #expect(model.phase == .paused(.takeoff, .card))
    }

    @Test func tappingTheNewMailInPlayHoldsTheGameAndAsks() throws {
        let model = try playing()
        let world = model.world
        model.leaveForMail()
        #expect(model.phase == .paused(.takeoff, .askingToLeave(staying: .countdown)))
        #expect(!model.canPause)
        run(model, for: 5)
        #expect(model.world == world)
    }

    @Test func stayingInTheGameCountsDownBeforeItCarriesOn() throws {
        let model = try playing()
        model.leaveForMail()
        model.stay()
        #expect(model.phase == .paused(.takeoff, .countingDown(left: 3)))
        run(model, for: PlaneGameHold.countdown + 1.0 / 60)
        #expect(model.phase == .flying(.takeoff))
    }

    @Test func stayingAfterAskingFromThePauseCardGoesBackToIt() throws {
        let model = try playing()
        model.pause()
        model.leaveForMail()
        #expect(model.phase == .paused(.takeoff, .askingToLeave(staying: .card)))
        model.stay()
        #expect(model.phase == .paused(.takeoff, .card))
    }

    @Test func leavingAfterTheQuestionFoldsBackHome() throws {
        let model = try playing()
        model.leaveForMail()
        model.exit()
        guard case .leaving(let leaving) = model.phase else {
            Issue.record("Expected to leave, got \(model.phase)")
            return
        }
        #expect(leaving.ending == nil)
    }

    @Test func theAppGoingInactiveLeavesTheQuestionUp() throws {
        let model = try playing()
        model.leaveForMail()
        model.pause()
        #expect(model.phase == .paused(.takeoff, .askingToLeave(staying: .countdown)))
    }

    @Test func theNewMailAfterAGameOverLeavesWithoutAsking() throws {
        let model = try playing()
        for _ in 0..<(60 * 600) where !model.isOver { model.tick(by: 1.0 / 60) }
        try #require(model.isOver)
        model.leaveForMail()
        guard case .leaving(let leaving) = model.phase else {
            Issue.record("Expected to leave, got \(model.phase)")
            return
        }
        #expect(leaving.ending != nil)
    }

    @Test func aDragWhilePausedDoesntSteerOnceTheGameCarriesOn() throws {
        let model = try playing()
        let x = model.world.plane.position.x
        model.pause()
        model.touch(sideways: 80)
        model.release()
        resume(model)
        model.tick(by: 1.0 / 60)
        #expect(model.world.plane.position.x == x)
    }

    @Test func theTakeoffPlaysOutBeforeAPause() throws {
        let model = try playing(takeoff: 0.5)
        model.pause()
        #expect(model.phase == .flying(.takeoff))
    }

    @Test func aGameAfterPlayAgainPausesAndResumesAsItself() throws {
        let model = try playing()
        for _ in 0..<(60 * 600) where !model.isOver { model.tick(by: 1.0 / 60) }
        try #require(model.isOver)
        model.playAgain()
        model.pause()
        #expect(model.phase == .paused(.again, .card))
        resume(model)
        #expect(model.phase == .flying(.again))
    }

    @Test func onlyAGameInPlayPauses() throws {
        let model = try playing()
        model.exit()
        let leaving = model.phase
        model.pause()
        #expect(model.phase == leaving)
        model.resume()
        #expect(model.phase == leaving)
    }

    @Test func theWayOutFromAPauseFoldsBackFromWhereThePlaneStopped() throws {
        let model = try playing()
        model.pause()
        model.exit()
        guard case .leaving(let leaving) = model.phase, case .home(let stage, let path) = leaving.way else {
            Issue.record("Expected to fold back home, got \(model.phase)")
            return
        }
        #expect(leaving.ending == nil)
        #expect(path == .landing(from: model.world.plane.position, to: stage.center))
        run(model, for: PlaneGameLanding.duration + 0.1)
        #expect(model.phase == .gone)
    }

    @Test func mailThatArrivesWhilePausedIsCounted() throws {
        let model = try playing()
        model.pause()
        threads.count = 2
        model.tick(by: 1.0 / 60)
        #expect(model.mailWaiting == 2)
        #expect(model.mailArrivals == 1)
    }

    @Test func theHintStaysAsItWasUnderThePauseCard() throws {
        let model = try playing(takeoff: PlaneGameTakeoff.duration + 1)
        let hint = model.hint
        try #require(hint > 0)
        model.pause()
        #expect(model.hint == hint)
        model.resume()
        run(model, for: 1)
        #expect(model.hint == hint)
    }

    @Test func aFingerLostWhileTheGameWasPausedStopsFiringOnceItCarriesOn() throws {
        let model = try playing()
        // The system cancels a drag when the app goes inactive, and the end of the touch never arrives.
        model.touch(sideways: 0)
        model.pause()
        resume(model)
        let shots = model.world.shots.count
        run(model, for: 1)
        #expect(model.world.shots.count <= shots)
    }

    @Test func aDragStillGoingOnAfterAResumeSteersFromWhereItIsWithoutAJump() throws {
        let model = try playing()
        model.touch(sideways: 0)
        model.touch(sideways: 40)
        model.tick(by: 1.0 / 60)
        let x = model.world.plane.position.x
        model.pause()
        resume(model)
        model.touch(sideways: 50)
        model.tick(by: 1.0 / 60)
        #expect(model.world.plane.position.x == x)
        model.touch(sideways: 60)
        model.tick(by: 1.0 / 60)
        #expect(abs(model.world.plane.position.x - (x + 10)) < 0.0001)
    }

    @Test func thePauseIsOnOfferOnlyWhileTheGameIsInPlay() throws {
        let model = try playing(takeoff: 0.5)
        #expect(!model.canPause)
        run(model, for: PlaneGameTakeoff.duration)
        #expect(model.canPause)
        model.pause()
        #expect(!model.canPause)
        resume(model)
        model.exit()
        #expect(!model.canPause)
    }

    @Test func aPausedGameDrawsWhatWasInPlay() throws {
        let model = try playing()
        let look = model.look
        model.pause()
        #expect(model.look == look)
        #expect(model.card == nil)
    }
}

extension PlaneGameModel {
    fileprivate var isOver: Bool {
        if case .over = phase { true } else { false }
    }
}

extension PlaneGamePhase {
    fileprivate var isPaused: Bool {
        if case .paused = self { true } else { false }
    }
}
