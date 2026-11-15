import MailCore

/// Where a thread stands in the list the reader sees it in, which decides what takes it out of the way there.
///
/// The list decides Trash and Spam, not the thread's labels: a thread carries the labels of all its messages, so one
/// whose earlier messages were trashed and whose reply then came in to the Inbox carries Trash while it sits in the
/// Inbox. Deleting it forever there would delete only the trashed messages, and the reply would come back.
nonisolated enum ThreadPlace: Equatable, Sendable {
    case trash
    case spam
    case inbox
    /// Archived, or seen through a label, Sent or a search.
    case elsewhere

    init(_ thread: ThreadSummary, in mailbox: Mailbox) {
        switch mailbox.labelID {
        case SystemLabel.trash: self = .trash
        case SystemLabel.spam: self = .spam
        default: self = thread.labelIDs.contains(SystemLabel.inbox) ? .inbox : .elsewhere
        }
    }

    /// What takes a thread out of the way here: out of Trash, or gone for good from it, out of Spam, or out of the
    /// Inbox.
    var awayActions: [ThreadAction] {
        switch self {
        case .trash: [.untrash, .deleteForever]
        case .spam: [.moveToInbox, .trash]
        case .inbox: [.archive, .trash]
        case .elsewhere: [.trash]
        }
    }

    /// Whether Report Spam means anything here: not for what is already in Spam or Trash.
    var canReportSpam: Bool { self == .inbox || self == .elsewhere }
}
