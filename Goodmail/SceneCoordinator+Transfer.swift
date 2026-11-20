import MailCore
import MailUI
import UIKit

/// The window's side of moving accounts between devices by QR code (`TransferScreens`).
extension SceneCoordinator {
    /// A link opened in this window: a transfer code the Camera app scanned, or a `mailto:` link.
    func open(_ link: URL) {
        if TransferInvitation(url: link) != nil {
            receiveTransfer(code: link)
        } else {
            compose(mailto: link)
        }
    }

    /// The Settings and Welcome entry points; `nil` in synthetic mailboxes, which have no sign-ins to move.
    var transferActions: TransferActions? {
        guard model.sharing != nil else { return nil }
        return TransferActions(
            send: { [weak self] in self?.sendTransfer() }, receive: { [weak self] in self?.receiveTransfer() })
    }

    /// Shows a code for another device to scan, and sends it the accounts the reader picks.
    func sendTransfer() {
        topViewController()?.present(TransferScreens.sending(model), animated: true)
    }

    /// Scans another device's code, or receives from `code` when the Camera app already scanned it. A code that comes
    /// while the receiving screen is up goes to that screen.
    func receiveTransfer(code: URL? = nil) {
        if let code, let receiving = receivingTransfer, receiving.screen != nil {
            receiving.model.use(code)
            return
        }
        let receiving = TransferScreens.receiving(model, code: code) { [weak self] in
            // A device that had no account shows the mail under the screen, ready when it closes.
            guard let self, case .welcome = screen, !model.accounts.isEmpty else { return }
            showMailbox()
        }
        receivingTransfer = ReceivingTransfer(screen: receiving.screen, model: receiving.model)
        topViewController()?.present(receiving.screen, animated: true)
    }
}
