import UIKit

/// A mailbox's list starts a message, fetches mail and searches from the keyboard.
extension MailboxViewController: KeyboardShortcutScreen {
    public func action(for shortcut: KeyboardShortcut) -> (() -> Void)? {
        switch shortcut {
        case .newMessage:
            return { [viewModel] in viewModel.compose() }
        case .getMail:
            // As pull to refresh: the view model owns the sync, and its failure shows on the health board.
            return { [viewModel] in Task { await viewModel.refresh() } }
        case .search:
            guard let search else { return nil }
            return { search.isActive = true }
        case .reply, .replyAll, .forward, .archive, .trash, .markUnread, .star, .send:
            return nil
        }
    }
}
