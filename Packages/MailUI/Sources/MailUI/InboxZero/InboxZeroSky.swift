import CoreGraphics
import Foundation
import Observation

/// The part of a window an empty Inbox's paper planes fly across: from beside the sidebar to the window's far edge,
/// over the list and the pane beside it, or the whole window when one screen fills it. The window's split view owns it
/// and draws it over its columns, and the Inbox list on show in the window lends it its scene.
@Observable final class InboxZeroSky {
    /// The Inbox scene on show in the window, if one is.
    private(set) var inbox: InboxZeroModel?
    /// Where the planes fly, in the window's coordinates.
    var frame = CGRect.zero

    /// A plane passes by itself a little less often than on the welcome screen, which is seen once.
    nonisolated static let passEvery: TimeInterval = 16

    /// The Inbox list showing `inbox` came on screen in the window.
    func attach(_ inbox: InboxZeroModel) {
        if self.inbox !== inbox { self.inbox = inbox }
    }

    /// The Inbox list showing `inbox` went off screen. Another may have come on in its place already.
    func detach(_ inbox: InboxZeroModel) {
        if self.inbox === inbox { self.inbox = nil }
    }

    /// The planes in the air at `now`, in the sky's own space, or `nil` while none can fly: no empty Inbox shows, the
    /// game has the envelopes, or the scene has no room for doodles.
    func flights(at now: Date, rightToLeft: Bool) -> DoodleScene? {
        guard let reach = inbox?.reach else { return nil }
        return DoodleScene(
            sky: frame, stage: reach.stage, pokes: reach.pokes.live, wake: reach.wake, clock: .running(now),
            rightToLeft: rightToLeft)
    }

    /// The planes in the air as the paper plane game takes over at `now`, for it to carry on.
    func handoff(at now: Date, rightToLeft: Bool) -> InboxZeroSkyHandoff? {
        flights(at: now, rightToLeft: rightToLeft).map { InboxZeroSkyHandoff(scene: $0, frame: frame) }
    }
}

/// An Inbox list's loan of its scene to its window's sky. It keeps the sky it lent to, because a list on its way out of
/// a window, replaced in its column or popped, has often left the stack by the time it hears, and can't find the sky
/// any more to take its scene back.
struct InboxZeroLoan {
    private weak var sky: InboxZeroSky?

    /// Lends `inbox` to the window's sky while it `shows`, and takes it back once it doesn't. `found` is the sky of the
    /// window the list is in now, or `nil` once it has left: then the scene comes back from the sky it was lent to.
    mutating func update(_ inbox: InboxZeroModel, found: InboxZeroSky?, shows: Bool) {
        if let found, found !== sky {
            sky?.detach(inbox)
            sky = found
        }
        if shows { sky?.attach(inbox) } else { sky?.detach(inbox) }
    }
}

/// The sky's planes as the game takes over: where they fly, and the sky's frame in the window.
nonisolated struct InboxZeroSkyHandoff: Equatable, Sendable {
    let scene: DoodleScene
    let frame: CGRect
}

nonisolated extension DoodleScene {
    /// The sky over a window at one instant, for its paper planes: `sky` is its frame and `stage` where the scene's
    /// envelopes are, both in the window's coordinates. A touch's plane takes off from under the finger and leaves by
    /// the sky's trailing edge, and one passing by itself comes in from its leading edge, low across the doodles'
    /// field.
    init(
        sky: CGRect, stage: InboxZeroStage, pokes: [DoodlePoke], wake: InboxZeroWake, clock: Clock, rightToLeft: Bool
    ) {
        let center = stage.center
        self.init(
            size: sky.size, pokes: pokes, clock: clock, rightToLeft: rightToLeft,
            focus: CGPoint(x: center.x - sky.minX, y: center.y - sky.minY), passInterval: InboxZeroSky.passEvery,
            quietFrom: wake.quietFrom, passesFrom: wake.passesFrom,
            passLane: stage.field.minY + stage.field.height * 0.8 - sky.minY)
    }
}
