/// What the Delete key does to the picked conversations in a Mac window: a choice of this Mac alone, since an
/// iPhone has no such key.
public enum DeleteKeyAction: String, CaseIterable, Sendable {
    case trash
    case archive

    public static let standard = DeleteKeyAction.trash

    /// What the key does in `mailbox`. Trash's own Delete is for good whichever is chosen, since archiving what is
    /// already in the trash would only take it out of sight. Spam's trashes, since archiving spam changes nothing.
    public func action(in mailbox: Mailbox) -> ThreadAction {
        switch mailbox.labelID {
        case SystemLabel.trash: return .deleteForever
        case SystemLabel.spam: return .trash
        default: break
        }
        switch self {
        case .trash: return .trash
        case .archive: return .archive
        }
    }
}
