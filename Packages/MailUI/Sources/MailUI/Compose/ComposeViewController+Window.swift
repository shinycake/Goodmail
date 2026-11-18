import UIKit

extension ComposeViewController {
    /// Beside Close, on iPad: moves the message into a window of its own, so it can be written beside the mail it
    /// answers or another message, as in Apple Mail.
    func ownWindowItem() -> UIBarButtonItem? {
        guard let open = openInOwnWindow, UIApplication.shared.supportsMultipleScenes else { return nil }
        let title = String(
            localized: "Open in New Window", table: "Compose", bundle: .module,
            comment: "Moves the message being written into a window of its own")
        let item = UIBarButtonItem(
            title: title, image: UIImage(systemName: "macwindow.badge.plus"),
            primaryAction: UIAction(title: title) { [weak self] _ in
                guard let self else { return }
                open(handOff())
            })
        item.accessibilityIdentifier = "compose.newWindow"
        return item
    }
}
