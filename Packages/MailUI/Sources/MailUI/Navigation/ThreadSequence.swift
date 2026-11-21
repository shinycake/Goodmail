public import MailCore

/// A list a window reads conversations from, as the window sees it when the reader puts the open one away: the rows
/// it goes on in, and the row it marks as read (R7, R11).
public protocol ThreadSequence: AnyObject {
    /// The rows a conversation opened from the list goes on in, top to bottom, as the list shows them now: the
    /// search results while search shows them.
    var frontRows: [ThreadSummary.ID] { get }
    /// The rows picked with a pointer, several of them and none read, top to bottom; empty otherwise.
    var pointerPick: [ThreadSummary.ID] { get }
    /// Shows `thread` as the one read, or with `nil` none, without opening anything.
    func mark(reading thread: ThreadSummary.ID?)
}
