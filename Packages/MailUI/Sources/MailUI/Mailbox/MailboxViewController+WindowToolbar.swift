import MailCore
import UIKit

/// On a desktop window the list's controls sit in the window's toolbar over it: the Inbox's category, the filter and
/// New Message, plain glyphs as in a Mac toolbar. The list has no bar at the bottom there; the sidebar's footer tells
/// of the accounts' problems.
extension MailboxViewController {
    /// New Message, for the bar at the bottom or, on a desktop window, the window's toolbar.
    func composeItem() -> UIBarButtonItem {
        UIBarButtonItem(
            title: String(localized: "New Message", table: "Mailbox", bundle: .module, comment: "Composer title"),
            image: UIImage(systemName: "square.and.pencil"),
            primaryAction: UIAction { [weak self] _ in self?.viewModel.compose() })
    }

    func windowComposeItem() -> UIBarButtonItem {
        let compose = composeItem()
        BarToolTips.set(compose, MailCommand.newMessage.toolTip)
        return compose
    }
}
