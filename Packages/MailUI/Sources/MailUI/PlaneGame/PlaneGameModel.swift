import Foundation
import PlaneGame
import SwiftUI
import UIKit

/// The paper plane game's state: the world, the phase and the game clock, stepped on by the screen's display link.
/// `tick(by:)` is the only place a phase changes apart from the reader's two choices, leaving and playing again.
@Observable final class PlaneGameModel {
    private(set) var phase: PlaneGamePhase = .flying(.takeoff)
    private(set) var world: PlaneGameWorld
    /// Seconds since the tenth tap: the sum of the steps, so tests drive it without a display.
    private(set) var clock: TimeInterval = 0
    /// The ring of doodles behind the game.
    private(set) var backdrop: PlaneGameBackdrop
    /// When a finger first moved the plane, on the game clock, which sends the hint away.
    private(set) var steeredAt: TimeInterval?
    /// Counters the screen plays a haptic on each change of: a kill, a pickup and a hit.
    private(set) var kills = 0
    private(set) var catches = 0
    private(set) var hits = 0
    /// Threads in the Inbox list the game came from, which was empty when it began: mail that arrived during the game.
    private(set) var mailWaiting = 0
    /// Counts the rises in `mailWaiting`, for a haptic and a hop on each.
    private(set) var mailArrivals = 0

    /// What the Inbox Zero scene drew at the tenth tap.
    let handoff: InboxZeroHandoff
    let reduceMotion: Bool
    /// Flight coordinates to the screen's and back.
    private(set) var mirror: PlaneGameMirror

    /// Points scrolled in games before this one, so the backdrop carries on from where it was after Play Again.
    @ObservationIgnored private var scrolledBefore: CGFloat = 0
    @ObservationIgnored private var finger = Finger.up
    /// How far the finger moved since the last step, in flight coordinates.
    @ObservationIgnored private var drag = CGSize.zero
    @ObservationIgnored private let list: PlaneGameList
    @ObservationIgnored private let defaults: UserDefaults

    /// The longest step the clock takes, so a hitch or a pause never teleports anything.
    static let longestStep: TimeInterval = 1.0 / 20
    /// The hint fades this long after the HUD is in, unless the plane moves first.
    static let hintStays: TimeInterval = 4

    private enum Finger: Equatable {
        case up
        /// Down, with the drag's translation from where it touched as of the last move.
        case down(CGSize)
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
        let field = Self.field(screen: screen, safeArea: safeArea, rightToLeft: handoff.scene.rightToLeft)
        let mirror = PlaneGameMirror(width: screen.width, rightToLeft: handoff.scene.rightToLeft)
        self.mirror = mirror
        // The plane folds out of the envelopes; with Reduce Motion on it is simply in its place.
        let launch = reduceMotion ? Self.startingPlace(in: field) : mirror.flipped(handoff.stage.center)
        world = PlaneGameWorld(
            field: field, launchingFrom: launch, after: reduceMotion ? 0 : PlaneGameTakeoff.planeSetsOff, seed: seed)
        backdrop = PlaneGameBackdrop(
            doodles: Doodle.inboxZero, handoff: handoff, screen: screen, band: field.band, reduceMotion: reduceMotion)
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
        case .flying(.again), .over: true
        case .leaving, .gone: false
        }
    }

    /// How much of "Drag to fly" shows: it comes in with the HUD and goes once the plane moves, or after a while.
    var hint: Double {
        guard case .flying(.takeoff) = phase else { return 0 }
        let goes = min(steeredAt ?? .infinity, PlaneGameTakeoff.duration + Self.hintStays)
        return takeoff.hud * (1 - PlaneGameEasing.ramp(clock, from: goes, to: goes + 0.3))
    }

    // MARK: The clock

    /// Moves the game on by `step` seconds, capped at `longestStep`.
    func tick(by step: TimeInterval) {
        let dt = min(max(step, 0), Self.longestStep)
        clock += dt
        notice(mail: list.threads())
        switch phase {
        case .flying:
            let input = PlaneGameInput(drag: drag, isFiring: finger != .up)
            drag = .zero
            answer(world.advance(by: dt, input: input))
            if world.isOver { phase = .over(PlaneGameBest.record(world.score, in: defaults)) }
        case .leaving(let leaving):
            // The scene underneath lays out after the game does, so it is asked every frame where its envelopes are.
            let landing = list.stage().map { leaving.landing(on: $0, mirror: mirror) } ?? leaving
            if clock - landing.since >= landing.duration(reduceMotion: reduceMotion) {
                phase = .gone
            } else if landing != leaving {
                phase = .leaving(landing)
            }
        case .over, .gone:
            break
        }
    }

    // MARK: The reader

    /// A finger is down and has dragged `translation` from where it touched, in the screen's coordinates.
    func touch(_ translation: CGSize) {
        let last = if case .down(let last) = finger { last } else { CGSize.zero }
        let moved = CGSize(width: translation.width - last.width, height: translation.height - last.height)
        finger = .down(translation)
        drag.width += mirror.rightToLeft ? -moved.width : moved.width
        drag.height += moved.height
        if steeredAt == nil, moved != .zero, case .flying = phase { steeredAt = clock }
    }

    /// The finger lifted: the fire stops and the plane holds its place.
    func release() {
        finger = .up
    }

    /// Asks for the way out. The takeoff plays out first, so the game always folds back from the game.
    func exit() {
        switch phase {
        case .flying(.takeoff) where !takeoff.isDone:
            return
        case .flying:
            phase = .leaving(PlaneGameLeaving(since: clock, way: wayOut(), ending: nil))
        case .over(let result):
            phase = .leaving(PlaneGameLeaving(since: clock, way: wayOut(), ending: result))
        case .leaving, .gone:
            return
        }
    }

    /// Sends a new plane in from beyond the leading edge, after a game over.
    func playAgain() {
        guard case .over = phase else { return }
        scrolledBefore += world.distance
        // A drag over the card steered nothing, so the new plane doesn't start with it.
        drag = .zero
        let start = Self.startingPlace(in: world.field)
        world = PlaneGameWorld(
            field: world.field, launchingFrom: CGPoint(x: -Self.offField, y: start.y), after: 0,
            seed: .random(in: .min ... .max))
        phase = .flying(.again)
    }

    /// The screen changed size, as on rotation.
    func resize(screen: CGSize, safeArea: UIEdgeInsets) {
        let field = Self.field(screen: screen, safeArea: safeArea, rightToLeft: mirror.rightToLeft)
        guard field != world.field else { return }
        world.resize(to: field)
        mirror = PlaneGameMirror(width: screen.width, rightToLeft: mirror.rightToLeft)
        backdrop.fit(mirror: mirror, band: field.band, at: distance)
    }

    // MARK: Helpers

    /// A plane that comes on from beyond the leading edge starts this far past it.
    private static let offField: CGFloat = 60

    /// The space the plane plays in: the screen, between the HUD and the home indicator, and clear of a camera
    /// housing on the side it flies from.
    static func field(screen: CGSize, safeArea: UIEdgeInsets, rightToLeft: Bool) -> PlaneGameField {
        let top = safeArea.top + 64
        let bottom = max(screen.height - safeArea.bottom - 24, top)
        return PlaneGameField(
            size: screen, band: top...bottom, leadingInset: rightToLeft ? safeArea.right : safeArea.left)
    }

    /// Where the plane's launch loop ends.
    static func startingPlace(in field: PlaneGameField) -> CGPoint {
        CGPoint(
            x: field.size.width * PlaneGameRules.startAt.x,
            y: min(max(field.size.height * PlaneGameRules.startAt.y, field.band.lowerBound), field.band.upperBound))
    }

    private func wayOut() -> PlaneGameLeaving.Way {
        guard let stage = list.stage() else { return .away }
        let home = mirror.flipped(stage.center)
        // After a game over there is no plane, so one flies in from beyond the leading edge.
        let from =
            if case .down = world.plane.status { CGPoint(x: -Self.offField, y: home.y) } else { world.plane.position }
        return .home(stage, path: LoopPath(from: from, to: home))
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
            case .caught: catches += 1
            case .hit: hits += 1
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
