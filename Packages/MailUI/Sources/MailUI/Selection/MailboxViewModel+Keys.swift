import MailCore

extension MailboxViewModel {
    /// Whether the list's `key` does anything now, in a window that `opensWindows` or not. Return and Delete act on
    /// listed rows only: a conversation still read after its row left is the reader's, so Delete goes on to the
    /// reader's own Trash rather than to nothing here.
    func answers(_ key: ListKey, opensWindows: Bool) -> Bool {
        switch (key, selection) {
        case (.up, _), (.down, _), (.extendUp, _), (.extendDown, _): !rows.isEmpty
        case (.drop, .several): true
        case (.openWindow, .reading): opensWindows && !selectedIDs.isEmpty
        case (.delete, .reading), (.delete, .several): actions != nil && !selectedIDs.isEmpty
        case (.drop, _), (.openWindow, _), (.delete, _): false
        }
    }
}
