import Foundation

/// How the Inbox came to be empty, which decides how the Inbox Zero scene comes on.
nonisolated enum InboxZeroArrival: Equatable, Sendable {
    /// The reader's own action on this list took its last thread away: the scene plays its full entrance.
    case earned
    /// It emptied some other way while on screen, as a sync or another device emptying it, or a switch to an empty
    /// category: the scene fades in.
    case found
    /// It was already empty when the list came on screen: the scene is simply there.
    case settled

    /// How long after the reader's rows left the scene still plays as earned, should it come on a moment after them.
    static let earnedWindow: Duration = .seconds(3)

    /// How a list that just became empty at `now` got there: whether it is `onScreen`, and whether the rows that left
    /// last were ones the reader took away.
    init(onScreen: Bool, removal: RecentRemoval, at now: ContinuousClock.Instant) {
        if !onScreen {
            self = .settled
        } else if case .took(let at) = removal, now - at <= Self.earnedWindow {
            self = .earned
        } else {
            self = .found
        }
    }
}
