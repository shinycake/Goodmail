/// The conversation a window reads, and the mailbox it is read in. The mailbox is the reader's own, apart from the
/// list beside it: a search result or a smart mailbox's conversation reads in All Mail over an Inbox, and one opened
/// from an alert reads where it is, so its toolbar and where it goes after Archive come back the same when the window
/// is rebuilt or restored.
public struct Reading: Hashable, Codable, Sendable {
    public var thread: ThreadSummary.ID
    public var mailbox: Mailbox

    public init(_ thread: ThreadSummary.ID, in mailbox: Mailbox) {
        self.thread = thread
        self.mailbox = mailbox
    }
}
