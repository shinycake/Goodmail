/// What dropping dragged conversations on a mailbox row does, decided once for the sidebar's rows to highlight or
/// refuse, and for the drop to carry out. Mail never crosses accounts: a row of another account, or one that blends
/// every account, refuses.
public enum MailDrop: Equatable, Sendable {
    /// The row takes no such drop.
    case refused
    /// The same change as the command, as Archive, Move to Trash and Report Spam do.
    case perform(ThreadAction)
    /// Moves the conversations to the place, leaving the mailbox they were dragged from.
    case move(MoveDestination)
    /// Gives the conversations the label and leaves them where they are.
    case addLabel(String)

    /// Whether the drop leaves the conversations where they were, which the pointer shows as a copy.
    public var isCopy: Bool {
        if case .addLabel = self { return true }
        return false
    }

    /// `adding` is the reader holding the option key, which adds a label where the account can keep several.
    /// `source` is the mailbox the conversations were dragged from.
    public init(
        dragging threads: [ThreadSummary.ID], from source: Mailbox, onto target: Mailbox, among accounts: [Account],
        adding: Bool
    ) {
        let owners = Set(threads.map(\.accountID))
        // The standard rows that name no account are the only account's, or a blend of several.
        let targetAccount = target.accountID ?? (accounts.count == 1 ? accounts.first?.id : nil)
        guard owners.count == 1, let owner = owners.first, owner == targetAccount,
            let service = accounts.first(where: { $0.id == owner })?.service,
            target.labelID != source.labelID
        else {
            self = .refused
            return
        }
        let leavingSpamOrTrash = source.labelID.map { [SystemLabel.spam, SystemLabel.trash].contains($0) } ?? false
        switch target.labelID {
        case nil:
            self = leavingSpamOrTrash ? .move(.archive) : .perform(.archive)
        case SystemLabel.inbox:
            self = .move(.inbox)
        case SystemLabel.trash:
            self = leavingSpamOrTrash ? .move(.trash) : .perform(.trash)
        case SystemLabel.spam:
            self = leavingSpamOrTrash ? .move(.spam) : .perform(.reportSpam)
        case SystemLabel.starred, SystemLabel.sent, SystemLabel.draft:
            self = .refused
        case let id?:
            self = adding && service.keepsMailUnderSeveralLabels ? .addLabel(id) : .move(.label(id))
        }
    }
}
