import MailCore

extension MailboxViewController {
    /// What an empty list shows in place of rows.
    nonisolated enum EmptyState: Equatable, Sendable {
        /// Spam and Trash start empty while their first page is fetched, and a list whose rows just went waits so for
        /// an older page on its way, which may bring more.
        case loading
        /// An Inbox the reader just cleared, while an older page that may bring more Inbox mail is on its way: a
        /// spinner, until the page comes or `pageWait` has passed since `since`, whichever is first.
        case awaitingPage(since: ContinuousClock.Instant)
        /// With another category that has unread mail to point to.
        case empty(pointingTo: InboxCategory?)
        /// The Inbox is clear, with another category that has unread mail to point to.
        case inboxZero(pointing: InboxZeroPointer?)
        /// The filter leaves nothing of the threads the mailbox has.
        case filtered(ListFilter)

        /// How long an Inbox just cleared waits for the older page on its way before its scene shows anyway. Short
        /// enough that the scene still counts as earned (`InboxZeroArrival.earnedWindow`).
        static let pageWait: Duration = .seconds(1)

        /// What shows at `now` while `rowsShown` says whether rows are on screen, `listing` what an empty list means,
        /// `showing` what shows now, and `settled` what an empty list of this mailbox shows once nothing more is
        /// coming.
        ///
        /// Rows just gone wait for the older page on its way behind a spinner, so an emptied Trash doesn't say it is
        /// empty before older threads come in, and a cleared Inbox doesn't play its scene only for the page's mail to
        /// pull it away. The Inbox waits at most `pageWait` rather than the length of a slow fetch, so the caller asks
        /// again once that has passed. An empty state already up stays while another page comes.
        static func next(
            rowsShown: Bool, listing: EmptyListing, showing: EmptyState?, settled: EmptyState,
            now: ContinuousClock.Instant
        ) -> EmptyState? {
            if rowsShown { return nil }
            switch listing {
            case .unknown:
                return nil
            case .firstPage:
                return .loading
            case .empty:
                return settled
            case .emptiedWhilePaging:
                switch (showing, settled) {
                case (.empty, _), (.inboxZero, _), (.filtered, _): return settled
                case (.awaitingPage(let since), .inboxZero):
                    return now - since >= pageWait ? settled : .awaitingPage(since: since)
                case (nil, .inboxZero), (.loading, .inboxZero): return .awaitingPage(since: now)
                case (nil, _), (.loading, _), (.awaitingPage, _): return .loading
                }
            }
        }
    }
}
