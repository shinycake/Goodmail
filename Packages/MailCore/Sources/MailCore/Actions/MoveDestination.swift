import Foundation

/// Where Move sends threads. Gmail has labels, not folders, so a move gives the thread the destination's label and
/// takes away the label of the mailbox it was moved from.
public enum MoveDestination: Hashable, Sendable {
    case inbox
    /// Out of the Inbox, with no label in its place.
    case archive
    case spam
    case trash
    /// A user label, by ID.
    case label(String)

    /// The destination a mailbox is, or `nil` for the ones that aren't places a thread can be moved to: Starred,
    /// Sent, Drafts and All Mail.
    public init?(_ mailbox: Mailbox) {
        switch mailbox.labelID {
        case SystemLabel.inbox: self = .inbox
        case SystemLabel.spam: self = .spam
        case SystemLabel.trash: self = .trash
        case nil, SystemLabel.starred, SystemLabel.sent, SystemLabel.draft: return nil
        case let id?: self = .label(id)
        }
    }

    /// The label this destination gives a thread; Archive gives none.
    var labelID: String? {
        switch self {
        case .inbox: SystemLabel.inbox
        case .archive: nil
        case .spam: SystemLabel.spam
        case .trash: SystemLabel.trash
        case .label(let id): id
        }
    }
}

extension ThreadAction {
    /// One change that moves threads from `mailbox` to `destination`.
    ///
    /// The thread loses the label of the mailbox it leaves. Starred, Sent, Drafts and All Mail aren't places, so a
    /// move from them takes the thread out of the Inbox instead, as Gmail does. Spam and Trash hold a thread on its
    /// own, so every move takes it out of both; Archive, Spam and Trash take it out of the Inbox too. Gmail's
    /// `threads.modify` adds and removes `SPAM` and `TRASH` like any label, so the whole move is one request.
    public static func move(to destination: MoveDestination, from mailbox: Mailbox) -> ThreadAction {
        let source = MoveDestination(mailbox)?.labelID ?? SystemLabel.inbox
        var remove: Set<String> = [source, SystemLabel.spam, SystemLabel.trash]
        switch destination {
        case .archive, .spam, .trash: remove.insert(SystemLabel.inbox)
        case .inbox, .label: break
        }
        let add: Set<String> = destination.labelID.map { [$0] } ?? []
        return .modifyLabels(add: add, remove: remove.subtracting(add))
    }
}
