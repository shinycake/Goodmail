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

    /// The reader's action counts as what emptied the list for this long after it.
    static let earnedWindow: Duration = .seconds(3)

    /// How a list that just became empty got there: whether it is `onScreen`, whether it was showing threads a moment
    /// ago, and how long ago the reader last took threads out of it, if they did.
    init(onScreen: Bool, hadThreads: Bool, sinceRemoval: Duration?) {
        if !onScreen {
            self = .settled
        } else if hadThreads, let sinceRemoval, sinceRemoval <= Self.earnedWindow {
            self = .earned
        } else {
            self = .found
        }
    }
}
