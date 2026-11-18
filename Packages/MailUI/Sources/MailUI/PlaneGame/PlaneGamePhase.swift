import Foundation
import PlaneGame

/// What the game screen is doing.
nonisolated enum PlaneGamePhase: Equatable, Sendable {
    /// In the air. The opening plays out by itself from the game clock.
    case flying(PlaneGameOpening)
    /// The plane is down and the card shows.
    case over(PlaneGameResult)
    /// Folding back into the Inbox, or flying off when the Inbox has mail.
    case leaving(PlaneGameLeaving)
    /// Finished: the screen hands back and dismisses.
    case gone
}

/// How the plane came to be in the air.
nonisolated enum PlaneGameOpening: Equatable, Sendable {
    /// Folded out of the Inbox's envelopes: the takeoff plays from the start of the game clock.
    case takeoff
    /// Play Again: a new plane flies in from beyond the leading edge, on paper that is already there.
    case again
}

/// How a game ended.
nonisolated struct PlaneGameResult: Equatable, Sendable {
    let score: Int
    /// The best score on this device, this game's included.
    let best: Int
    /// This game set the best score.
    let isNewBest: Bool
}

/// The way out, from the moment it was asked for.
nonisolated struct PlaneGameLeaving: Equatable, Sendable {
    nonisolated enum Way: Equatable, Sendable {
        /// Folding back into the Inbox Zero scene laid out on `stage`, on the screen, with the plane flying `path`, in
        /// flight coordinates, onto its envelopes.
        case home(InboxZeroStage, path: LoopPath)
        /// The Inbox has mail again, so there is nothing to fold back into: the plane flies off and the paper fades.
        case away
    }

    /// When the exit was asked for, on the game clock.
    let since: TimeInterval
    let way: Way
    /// The game over card it left from, which fades with what was in play, or `nil` when it left mid-game.
    let ending: PlaneGameResult?

    /// The same way out, folding back into the envelopes on `stage` instead, as when the Inbox lays out again while
    /// the plane is on its way home. The plane's loop keeps its start and heads for the new place, in flight
    /// coordinates through `mirror`.
    func landing(on stage: InboxZeroStage, mirror: PlaneGameMirror) -> PlaneGameLeaving {
        guard case .home(let landingOn, let path) = way, landingOn != stage else { return self }
        return PlaneGameLeaving(
            since: since, way: .home(stage, path: LoopPath(from: path.start, to: mirror.flipped(stage.center))),
            ending: ending)
    }

    /// How much of what was in play still shows, `elapsed` seconds into the way out.
    func play(at elapsed: TimeInterval, reduceMotion: Bool) -> Double {
        switch way {
        case .home: PlaneGameLanding(elapsed: elapsed, reduceMotion: reduceMotion).play
        case .away: PlaneGameFlyOff(elapsed: elapsed).paper
        }
    }

    /// How long the way out takes.
    func duration(reduceMotion: Bool) -> TimeInterval {
        switch way {
        case .home: PlaneGameLanding(elapsed: 0, reduceMotion: reduceMotion).length
        case .away: PlaneGameFlyOff.duration
        }
    }
}

/// The game over card as drawn: the result and how much of it shows.
nonisolated struct PlaneGameCard: Equatable, Sendable {
    let result: PlaneGameResult
    let opacity: Double
}

extension PlaneGamePhase {
    /// The game over card at `clock`: all of it while the game is over, then fading with what was in play on the way
    /// out, so it never leaves ahead of the rest.
    func card(at clock: TimeInterval, reduceMotion: Bool) -> PlaneGameCard? {
        switch self {
        case .over(let result):
            PlaneGameCard(result: result, opacity: 1)
        case .leaving(let leaving):
            leaving.ending.map {
                PlaneGameCard(
                    result: $0, opacity: leaving.play(at: clock - leaving.since, reduceMotion: reduceMotion))
            }
        case .flying, .gone:
            nil
        }
    }
}
