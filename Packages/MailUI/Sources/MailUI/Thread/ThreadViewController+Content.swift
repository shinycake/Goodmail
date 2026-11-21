import MailCore
import UIKit

/// A conversation with nothing to show says why, over the reader, as the system's empty states do: one deleted is no
/// longer available, and one that couldn't be fetched offers to try again (R10).
extension ThreadViewController {
    /// Shows what `viewModel.content` says, in `updateProperties`, so it follows each change.
    func showContent() {
        guard case .unavailable(let why) = viewModel.content else {
            contentUnavailableConfiguration = nil
            return
        }
        var empty = UIContentUnavailableConfiguration.empty()
        switch why {
        case .gone:
            empty.image = UIImage(systemName: "tray")
            empty.text = String(
                localized: "This Conversation Is No Longer Available", table: "ThreadContent", bundle: .module,
                comment: "Title over a conversation that was deleted while open, or before it could be opened")
            empty.secondaryText = String(
                localized: "It may have been deleted.", table: "ThreadContent", bundle: .module,
                comment: "Under the title over a conversation that is no longer available")
        case .unreachable:
            empty.image = UIImage(systemName: "wifi.exclamationmark")
            empty.text = String(
                localized: "Couldn’t Load This Conversation", table: "ThreadContent", bundle: .module,
                comment: "Title over a conversation whose messages couldn't be fetched")
            empty.secondaryText = String(
                localized: "Check your connection and try again.", table: "ThreadContent", bundle: .module,
                comment: "Under the title over a conversation whose messages couldn't be fetched")
            var retry = UIButton.Configuration.borderedProminent()
            retry.title = String(
                localized: "Try Again", table: "ThreadContent", bundle: .module,
                comment: "Fetches a conversation's messages again")
            empty.button = retry
            empty.buttonProperties.primaryAction = UIAction { [weak self] _ in self?.loadAgain() }
        }
        contentUnavailableConfiguration = empty
    }
}
