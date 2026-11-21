/// What a change the reader asks of the conversation they're reading does to the reader (R7, R8).
public enum ReaderExit: Equatable, Sendable {
    /// The reader stays on it: a star, a read mark, a label added, a change that leaves it where it is read.
    case stays
    /// The conversation is put away, so the window moves on as Settings says (`AfterRemoval`): archived, trashed,
    /// deleted forever, reported as spam, muted, snoozed, moved, its sender blocked, or a label it is read under
    /// taken off.
    case putAway
    /// Marked unread, kept for later: the window goes back to the list.
    case setAside

    /// What `request` does to the reader of a conversation carrying `labels`, read in `mailbox`.
    public static func exit(after request: MailChange.Request, labels: Set<String>, readIn mailbox: Mailbox)
        -> ReaderExit
    {
        if let exit = exit(after: request) { return exit }
        guard case .action(let action) = request else { return .stays }
        switch action.outcome(for: labels) {
        case .deleted:
            return .putAway
        case .labeled(let after):
            return mailbox.contains(labels: labels) && !mailbox.contains(labels: after) ? .putAway : .stays
        }
    }

    /// What `request` does wherever the conversation is read, or `nil` when that depends on its labels: a label
    /// change puts it away only when it takes it out of the mailbox it is read in.
    public static func exit(after request: MailChange.Request) -> ReaderExit? {
        switch request {
        case .move, .snooze, .block:
            return .putAway
        case .unsnooze:
            return .stays
        case .action(let action):
            if action == .markRead(false) { return .setAside }
            if puttingAway.contains(action) { return .putAway }
            // Unstarring in Starred takes the row away but leaves the reader on it.
            if action == .markRead(true) || action == .star(true) || action == .star(false) { return .stays }
            return nil
        }
    }

    /// The actions that put a conversation away wherever it is read, even where its row stays, as Archive in All Mail.
    private static let puttingAway: [ThreadAction] = [.archive, .trash, .deleteForever, .reportSpam, .mute]
}
