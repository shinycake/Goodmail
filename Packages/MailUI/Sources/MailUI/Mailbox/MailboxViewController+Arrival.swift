public import MailCore
import UIKit

extension MailboxViewController {
    /// Ends search and Select mode, so the list shows its own rows and the conversation an arrival from outside opens
    /// is revealed among them (R3). Search tells the window it ended, as when the reader cancels it.
    public func endSearchAndSelection() {
        if isEditing { setEditing(false, animated: true) }
        searchToBegin = nil
        guard let search, search.isActive else { return }
        search.isActive = false
    }

    /// Shows `category` when the list is an Inbox split into categories, as the window's state says after an arrival
    /// for a conversation in another one (R4). The pick reaches the window as the reader's own would, which then
    /// changes nothing.
    public func showCategory(_ category: InboxCategory) {
        guard viewModel.category != nil, viewModel.category != category else { return }
        viewModel.select(category)
    }
}
