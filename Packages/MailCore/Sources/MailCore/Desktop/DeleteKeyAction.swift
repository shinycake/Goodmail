/// What the Delete key does to the picked conversations in a Mac window: a choice of this Mac alone, since an
/// iPhone has no such key.
public enum DeleteKeyAction: String, CaseIterable, Sendable {
    case trash
    case archive

    public static let standard = DeleteKeyAction.trash

    /// What the key does in a mailbox. Trash's own Delete is for good whichever is chosen, since archiving what is
    /// already in the trash would only take it out of sight.
    public func action(inTrash: Bool) -> ThreadAction {
        if inTrash { return .deleteForever }
        switch self {
        case .trash: return .trash
        case .archive: return .archive
        }
    }
}
