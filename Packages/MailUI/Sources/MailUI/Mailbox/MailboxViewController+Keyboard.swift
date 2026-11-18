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
            // Typing goes straight into the field, as after a tap on it.
            return {
                search.isActive = true
                search.searchBar.becomeFirstResponder()
            }
        case .previousThread, .nextThread:
            return step(by: shortcut == .nextThread ? 1 : -1)
        case .reply, .replyAll, .forward, .archive, .trash, .markUnread, .star, .send, .newWindow, .closeWindow,
            .settings:
            return nil
        }
    }

    /// Opens the thread `offset` rows from the open one, selecting its row, or `nil` past either end or while
    /// selecting several.
    private func step(by offset: Int) -> (() -> Void)? {
        guard !isEditing, let target = viewModel.thread(offset, from: selectedIDs.first),
            let indexPath = dataSource.indexPath(for: target)
        else { return nil }
        return { [weak self] in
            self?.collectionView.selectItem(at: indexPath, animated: true, scrollPosition: .centeredVertically)
            self?.viewModel.open(target)
        }
    }
}
