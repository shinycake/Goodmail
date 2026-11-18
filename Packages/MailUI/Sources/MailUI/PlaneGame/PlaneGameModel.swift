import Foundation
import PlaneGame
import SwiftUI
import UIKit

/// The paper plane game's state: the world, the phase and the game clock, stepped on by the screen's display link.
/// `tick(by:)` is the only place a phase changes apart from the reader's choices: pausing, carrying on, leaving and
/// playing again.
@Observable final class PlaneGameModel {
    private(set) var phase: PlaneGamePhase = .flying(.takeoff)
    private(set) var world: PlaneGameWorld
    /// Seconds since the tenth tap: the sum of the steps, so tests drive it without a display.
    private(set) var clock: TimeInterval = 0
    /// The ring of doodles behind the game.
    private(set) var backdrop: PlaneGameBackdrop
    /// When a finger first moved the plane, on the game clock, which sends the hint away.
    private(set) var steeredAt: TimeInterval?
    /// Counters the screen plays a haptic on each change of: a kill, a pickup or power-up, a hit and a beaten boss.
    private(set) var kills = 0
    private(set) var catches = 0
    private(set) var hits = 0
    private(set) var bossesDown = 0
    /// Threads in the Inbox list the game came from, which was empty when it began: mail that arrived during the game.
    private(set) var mailWaiting = 0
    /// Counts the rises in `mailWaiting`, for a haptic and a hop on each.
    private(set) var mailArrivals = 0

    /// What the Inbox Zero scene drew at the tenth tap.
    let handoff: InboxZeroHandoff
    let reduceMotion: Bool

    /// Points scrolled in games before this one, so the backdrop carries on from where it was after Play Again.
    @ObservationIgnored private var scrolledBefore: CGFloat = 0
    @ObservationIgnored private var finger = Finger.up
    /// How far the finger moved sideways since the last step.
    @ObservationIgnored private var slide: CGFloat = 0
    @ObservationIgnored private let list: PlaneGameList
    @ObservationIgnored private let defaults: UserDefaults

    /// The longest step the clock takes, so a hitch or a pause never teleports anything.
    static let longestStep: TimeInterval = 1.0 / 20
    /// The hint fades this long after the HUD is in, unless the plane moves first.
    static let hintStays: TimeInterval = 4

    private enum Finger: Equatable {
        case up
        /// Down, with how far it has moved sideways from where it touched, as of the last move.
        case down(CGFloat)
    }

    /// A game taking over from `handoff` on a screen `screen` in size, with `safeArea` kept clear of the plane.
    /// `list` answers the questions the game asks the list it came from as it plays.
    init(
        handoff: InboxZeroHandoff, screen: CGSize, safeArea: UIEdgeInsets, reduceMotion: Bool, list: PlaneGameList,
        defaults: UserDefaults = .standard, seed: UInt64 = .random(in: .min ... .max)
    ) {
        self.handoff = handoff
        self.reduceMotion = reduceMotion
        self.list = list
        self.defaults = defaults
        // The plane folds out of the envelopes; with Reduce Motion on it is simply in its place.
        world = PlaneGameWorld(
            field: Self.field(screen: screen, safeArea: safeArea),
            launch: reduceMotion ? .inPlace : .unfolding(at: handoff.stage.center),
            after: reduceMotion ? 0 : PlaneGameTakeoff.planeSetsOff, seed: seed)
        backdrop = PlaneGameBackdrop(
            doodles: Doodle.inboxZero, handoff: handoff, screen: screen, reduceMotion: reduceMotion)
    }

    /// The takeoff as of now.
    var takeoff: PlaneGameTakeoff { PlaneGameTakeoff(elapsed: clock, reduceMotion: reduceMotion) }

    /// The game over card as of now.
    var card: PlaneGameCard? { phase.card(at: clock, reduceMotion: reduceMotion) }

    /// Points the world has scrolled in every game since the takeoff, which the backdrop is drawn from.
    var distance: CGFloat { scrolledBefore + world.distance }

    /// Whether the paper covers the window, so the status bar and home indicator step back.
    var coversWindow: Bool {
        switch phase {
        case .flying(.takeoff): takeoff.paper >= 1
        case .flying(.again), .paused, .over: true
        case .leaving, .gone: false
        }
    }

    /// How much of "Drag to fly" shows: it comes in with the HUD and goes once the plane moves, or after a while.
    var hint: Double {
        guard case .flying(.takeoff) = phase else { return 0 }
        let goes = min(steeredAt ?? .infinity, PlaneGameTakeoff.duration + Self.hintStays)
        return takeoff.hud * (1 - PlaneGameEasing.ramp(clock, from: goes, to: goes + 0.3))
    }

    /// Where "Drag to fly" sits: across the middle, 60% of the way down, clear of the plane on its row.
    var hintCenter: CGPoint {
        CGPoint(x: world.field.size.width / 2, y: world.field.size.height * 0.6)
    }

    // MARK: The clock

    /// Moves the game on by `step` seconds, capped at `longestStep`.
    func tick(by step: TimeInterval) {
        notice(mail: list.threads())
        // A paused game holds its clock too, so nothing drawn from it moves either.
        if case .paused = phase { return }
        let dt = min(max(step, 0), Self.longestStep)
        clock += dt
        switch phase {
        case .flying:
            let input = PlaneGameInput(slide: slide, isFiring: finger != .up)
            slide = 0
            answer(world.advance(by: dt, input: input))
            if world.isOver { phase = .over(PlaneGameBest.record(world.score, in: defaults)) }
        case .leaving(let leaving):
            // The scene underneath lays out after the game does, so it is asked every frame where its envelopes are.
            let landing = list.stage().map { leaving.landing(on: $0) } ?? leaving
            if clock - landing.since >= landing.duration(reduceMotion: reduceMotion) {
                phase = .gone
            } else if landing != leaving {
                phase = .leaving(landing)
            }
        case .paused, .over, .gone:
            break
        }
    }

    // MARK: The reader

    /// A finger is down and has moved `sideways` points to the right of where it touched. Only the sideways
    /// movement steers: the plane keeps its height.
    func touch(sideways: CGFloat) {
        let last = if case .down(let last) = finger { last } else { CGFloat(0) }
        let moved = sideways - last
        finger = .down(sideways)
        slide += moved
        if steeredAt == nil, moved != 0, case .flying = phase { steeredAt = clock }
    }

    /// The finger lifted: the fire stops and the plane holds its place.
    func release() {
        finger = .up
    }

    /// Holds the game still until `resume()`. The takeoff plays out first, and only a game in play pauses.
    func pause() {
        switch phase {
        case .flying(.takeoff) where !takeoff.isDone:
            return
        case .flying(let opening):
            phase = .paused(opening)
        case .paused, .over, .leaving, .gone:
            return
        }
    }

    /// Carries on from the pause.
    func resume() {
        guard case .paused(let opening) = phase else { return }
        // A drag over the card steered nothing, so the plane doesn't start with it.
        slide = 0
        phase = .flying(opening)
    }

    /// Asks for the way out. The takeoff plays out first, so the game always folds back from the game.
    func exit() {
        switch phase {
        case .flying(.takeoff) where !takeoff.isDone:
            return
        case .flying, .paused:
            phase = .leaving(PlaneGameLeaving(since: clock, way: wayOut(), ending: nil))
        case .over(let result):
            phase = .leaving(PlaneGameLeaving(since: clock, way: wayOut(), ending: result))
        case .leaving, .gone:
            return
        }
    }

    /// Sends a new plane up from below the bottom edge, after a game over.
    func playAgain() {
        guard case .over = phase else { return }
        scrolledBefore += world.distance
        // A drag over the card steered nothing, so the new plane doesn't start with it.
        slide = 0
        world = PlaneGameWorld(field: world.field, launch: .fromBelow, after: 0, seed: .random(in: .min ... .max))
        phase = .flying(.again)
    }

    /// The screen changed size, as on rotation.
    func resize(screen: CGSize, safeArea: UIEdgeInsets) {
        let field = Self.field(screen: screen, safeArea: safeArea)
        guard field != world.field else { return }
        world.resize(to: field)
        backdrop.fit(size: screen, at: distance)
    }

    // MARK: Helpers

    /// The space the plane plays in: the screen, its lanes clear of the side safe areas, its ceiling under the HUD
    /// and its row above the home indicator with room for a thumb.
    static func field(screen: CGSize, safeArea: UIEdgeInsets) -> PlaneGameField {
        PlaneGameField(
            size: screen, safeTop: safeArea.top, safeLeft: safeArea.left, safeBottom: safeArea.bottom,
            safeRight: safeArea.right)
    }

    private func wayOut() -> PlaneGameLeaving.Way {
        guard let stage = list.stage() else { return .away }
        let home = stage.center
        // After a game over there is no plane, so one comes straight up from below the bottom edge.
        if case .down = world.plane.status {
            let below = CGPoint(x: home.x, y: world.field.size.height + PlaneGameRules.belowField)
            return .home(stage, path: .straight(from: below, to: home))
        }
        return .home(stage, path: .landing(from: world.plane.position, to: home))
    }

    /// The list now shows `threads` threads. The game never pauses for them; the HUD says so, quietly.
    private func notice(mail threads: Int) {
        guard threads != mailWaiting else { return }
        if threads > mailWaiting { mailArrivals += 1 }
        mailWaiting = threads
    }

    private func answer(_ events: [PlaneGameEvent]) {
        for event in events {
            switch event {
            case .shotDown: kills += 1
            case .caught, .powered: catches += 1
            case .hit: hits += 1
            case .bossDown: bossesDown += 1
            case .fell: break
            }
        }
    }
}

/// What the game asks the list it was started from, as it plays.
struct PlaneGameList {
    /// Where the Inbox Zero scene's envelopes and doodles are on the screen now, or `nil` when no scene shows because
    /// the Inbox has mail again.
    let stage: () -> InboxZeroStage?
    /// How many threads the list shows now. It was empty when the game began, so every one is new mail.
    let threads: () -> Int
}
