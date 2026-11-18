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

/// The Inbox Zero scene's state, which the mailbox list sets and the scene draws.
@Observable final class InboxZeroModel {
    /// What shows, or `nil` while the Inbox has mail.
    var showing: InboxZeroShowing?
    /// The list's bars, which the scene keeps clear of.
    var insets = EdgeInsets()
    /// Switches the list to a category.
    @ObservationIgnored var go: (InboxCategory) -> Void = { _ in }
    /// Whether the paper plane game is up. It draws the envelopes, doodles and planes then, so the scene doesn't.
    var isPlaying = false
    /// Where the scene's envelopes and doodles are, in the scene's own space, as it last laid out. The game takes over
    /// from here and folds back to here. Not observed: nothing draws from it.
    @ObservationIgnored var stage: InboxZeroStage?
    /// Starts the game. The list sets it.
    @ObservationIgnored var play: (InboxZeroHandoff) -> Void = { _ in }
}
