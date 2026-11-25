import Foundation
import MailCore
import SwiftUI

/// What the Inbox Zero scene shows while the Inbox is empty.
nonisolated struct InboxZeroShowing: Equatable, Sendable {
    let arrival: InboxZeroArrival
    let arrivedAt: Date
    /// Another category with unread mail, when there is one to point to.
    var pointing: InboxZeroPointer?
}

/// A category with unread mail, for an empty Primary to point to.
nonisolated struct InboxZeroPointer: Equatable, Sendable {
    let category: InboxCategory
    let unread: Int
}

/// Where the Inbox Zero scene stands. One value, so a touch can't land on a scene the game has taken over and the
/// drift can't outlive the scene it belongs to.
nonisolated enum InboxZeroState: Equatable, Sendable {
    /// The Inbox has mail, and the game isn't up.
    case away
    /// The Inbox is empty and the scene alive to touch: `pokes` still playing out, measured from the middle of the
    /// envelopes, and whether it is moving.
    case live(InboxZeroShowing, wake: InboxZeroWake, pokes: DoodlePokes)
    /// The paper plane game is up and draws the envelopes, doodles and planes, over the scene the Inbox shows when it is
    /// still empty under it, or none when mail is waiting.
    case game(InboxZeroShowing?)
}

/// The scene alive to touch with room for doodles, which is when the window's sky flies its planes and the pane beside
/// the list carries its doodles on.
nonisolated struct InboxZeroReach: Equatable, Sendable {
    let showing: InboxZeroShowing
    let wake: InboxZeroWake
    let pokes: DoodlePokes
    /// Where the scene's envelopes and doodles are, in the window's coordinates.
    let stage: InboxZeroStage
}

/// The Inbox Zero scene's state, which the mailbox list sets and the scene draws. It lives here rather than in the
/// scene's view because the scene reaches past the list: the window's sky flies the planes its touches send off, and
/// the pane beside the list carries its doodles on, all playing the same touches on the same clock.
@Observable final class InboxZeroModel {
    /// Changed only by the transitions below.
    private(set) var state = InboxZeroState.away
    /// The list's bars and whatever covers its sides, which the scene keeps clear of.
    var insets = EdgeInsets()
    /// Where the scene's envelopes and doodles are in the window, or `nil` before the scene has laid out. It goes stale
    /// while the list is off screen, when nothing reads it: the list takes its scene back from the sky as it goes.
    var onScreen: InboxZeroStage?
    /// Switches the list to a category.
    @ObservationIgnored var go: (InboxCategory) -> Void = { _ in }
    /// Where the scene's envelopes and doodles are, in the scene's own space, as it last laid out. The game takes over
    /// from here and folds back to here, and the scene draws from it. Only the scene's layout sets it.
    var stage: InboxZeroStage? {
        didSet { if stage != oldValue { laidOut() } }
    }
    /// Called when the scene lays out anew, so the list can say where it is in the window.
    @ObservationIgnored var laidOut: () -> Void = {}
    /// Starts the game. The list sets it.
    @ObservationIgnored var play: (InboxZeroHandoff) -> Void = { _ in }

    /// What shows, or `nil` while the Inbox has mail.
    var showing: InboxZeroShowing? {
        switch state {
        case .away: nil
        case .live(let showing, _, _): showing
        case .game(let showing): showing
        }
    }

    /// Whether the paper plane game is up.
    var isPlaying: Bool {
        if case .game = state { true } else { false }
    }

    /// Whether the scene is moving: asleep unless it is alive to touch.
    var wake: InboxZeroWake {
        if case .live(_, let wake, _) = state { wake } else { .asleep }
    }

    /// The touches still playing out on the scene.
    var pokes: [DoodlePoke] {
        if case .live(_, _, let pokes) = state { pokes.live } else { [] }
    }

    /// The scene alive to touch with room for doodles, or `nil`.
    var reach: InboxZeroReach? {
        guard case .live(let showing, let wake, let pokes) = state, let stage = onScreen, stage.layout.hasDoodles
        else { return nil }
        return InboxZeroReach(showing: showing, wake: wake, pokes: pokes, stage: stage)
    }

    /// The Inbox has just emptied, as `showing` says. The scene comes on awake, unless the game is up, as when mail
    /// came and went during it: then it waits for the game to hand back. An Inbox the reader just cleared sees a plane
    /// off, unless there's still unread mail to point to.
    func arrive(_ showing: InboxZeroShowing) {
        if case .game = state {
            state = .game(showing)
            return
        }
        let driftStarts: Date? =
            switch showing.arrival {
            case .earned: showing.arrivedAt + InboxZeroEntrance.driftStarts
            case .found: showing.arrivedAt
            case .settled: nil
            }
        var pokes = DoodlePokes()
        if showing.arrival == .earned, showing.pointing == nil {
            pokes.land(offset: .zero, time: showing.arrivedAt + InboxZeroEntrance.planeLeaves)
        }
        state = .live(showing, wake: .awake(since: showing.arrivedAt, rampFrom: driftStarts), pokes: pokes)
    }

    /// Another category gained or lost unread mail while the Inbox stays empty.
    func point(to pointing: InboxZeroPointer?) {
        switch state {
        case .away, .game(nil):
            break
        case .live(var showing, let wake, let pokes):
            showing.pointing = pointing
            state = .live(showing, wake: wake, pokes: pokes)
        case .game(var showing?):
            showing.pointing = pointing
            state = .game(showing)
        }
    }

    /// Mail arrived, so the scene goes.
    func leave() {
        state = isPlaying ? .game(nil) : .away
    }

    /// A touch `offset` from the middle of the envelopes, on the scene or beside it: the doodles near it are pushed
    /// aside, the envelopes nod and a plane sets off from under the finger. Only a live scene takes touches.
    func poke(at offset: CGSize) {
        guard case .live(let showing, let wake, var pokes) = state else { return }
        let now = Date.now
        pokes.land(offset: offset, time: now)
        state = .live(showing, wake: wake.woken(at: now), pokes: pokes)
    }

    /// Keeps a live scene drifting, as a touch does.
    func wakeUp() {
        guard case .live(let showing, let wake, let pokes) = state else { return }
        state = .live(showing, wake: wake.woken(at: .now), pokes: pokes)
    }

    /// The scene has drifted to a stop.
    func rest() {
        guard case .live(let showing, _, let pokes) = state else { return }
        state = .live(showing, wake: .asleep, pokes: pokes)
    }

    /// The game came up or went. It hands back with everything at rest, so the drift eases in from there.
    func setPlaying(_ playing: Bool) {
        switch (state, playing) {
        case (.away, true):
            state = .game(nil)
        case (.live(let showing, _, _), true):
            state = .game(showing)
        case (.game(let showing?), false):
            state = .live(showing, wake: InboxZeroWake.asleep.woken(at: .now), pokes: DoodlePokes())
        case (.game(nil), false):
            state = .away
        case (.away, false), (.live, false), (.game, true):
            break
        }
    }
}
