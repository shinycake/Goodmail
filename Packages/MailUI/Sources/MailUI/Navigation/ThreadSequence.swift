public import MailCore

/// A list a window reads conversations from, as the window sees it when the reader puts the open one away: the rows
/// it goes on in, where they are read, and the row it marks as read (R7, R11).
public protocol ThreadSequence: AnyObject {
    /// The rows a conversation opened from the list goes on in, top to bottom, as the list shows them now: the
    /// search results while search shows them.
    var frontRows: [ThreadSummary.ID] { get }
    /// Where a conversation of `frontRows` is read: the list's own mailbox, or All Mail for search results and
    /// snoozed conversations.
    var frontMailbox: Mailbox { get }
    /// The rows picked with a pointer, several of them and none read, top to bottom; empty otherwise.
    var pointerPick: [ThreadSummary.ID] { get }
    /// Whether `frontRows` are search's results over the list rather than its own rows, so a conversation opened from
    /// one goes on in the rows it was opened from only while they show.
    var frontSearching: Bool { get }
    /// The row of `thread` as the list holds it, so the window opens it without reading the store; `nil` when the
    /// list doesn't hold it.
    func summary(of thread: ThreadSummary.ID) -> ThreadSummary?
    /// Shows `thread` as the one read, or with `nil` none, without opening anything. It holds at once, before the
    /// row is listed, so a row that comes back later, as after Undo, is marked then.
    func mark(reading thread: ThreadSummary.ID?)
    /// Picks `rows` again, top to bottom, as Undo brings back rows an action took from a pointer's pick. Rows not
    /// listed yet are picked as they come back. A list that picks no rows with a pointer does nothing.
    func repick(_ rows: [ThreadSummary.ID])
}

extension ThreadSequence {
    public func repick(_ rows: [ThreadSummary.ID]) {}

    /// The list as the window's navigation reads it.
    public var navigationFront: WindowNavigation.Front {
        WindowNavigation.Front(
            rows: frontRows, pointerPick: pointerPick, mailbox: frontMailbox, searching: frontSearching)
    }
}
