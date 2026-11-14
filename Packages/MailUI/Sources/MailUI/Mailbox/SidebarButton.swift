import UIKit

extension UIViewController {
    /// The button that goes back to the mailboxes, standing in for the back button of a mail list pushed over them: a
    /// sidebar symbol in the same glass as the category pill beside it, since on a phone the mailboxes list is the
    /// app's sidebar. `nil` when the list is its stack's root, as in the wide arrangement. The leading symbol mirrors
    /// itself in right-to-left languages.
    func sidebarBackItem() -> UIBarButtonItem? {
        guard let navigationController, navigationController.viewControllers.first !== self else { return nil }
        let item = UIBarButtonItem(
            image: UIImage(systemName: "sidebar.leading"),
            primaryAction: UIAction { [weak navigationController] _ in
                navigationController?.popViewController(animated: true)
            })
        item.accessibilityLabel = String(
            localized: "Mailboxes", table: "Mailbox", bundle: .module,
            comment: "VoiceOver: the button that goes back to the list of mailboxes")
        item.accessibilityIdentifier = "mailboxesSidebar"
        return item
    }
}
