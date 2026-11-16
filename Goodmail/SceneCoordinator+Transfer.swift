import LocalAuthentication
import MailCore
import MailUI
import UIKit
import os

/// The window's side of moving accounts between devices by QR code.
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
        let model = model
        let accounts = model.accounts
        let sending = TransferSending(
            accounts: accounts, unlock: { await Self.unlockAsOwner() },
            host: {
                let host = TransferHost { try await AppModel.transferPayload(of: accounts, chosen: $0) }
                #if DEBUG
                    // A simulator can't scan, so testing a transfer between two opens this code on the other.
                    Logger.sharing.debug("Transfer code: \(host.code, privacy: .public)")
                #endif
                return host
            })
        topViewController()?.present(TransferSendScreen.make(model: sending), animated: true)
    }

    /// Scans another device's code, or receives from `code` when the Camera app already scanned it. A code that comes
    /// while the receiving screen is up goes to that screen.
    func receiveTransfer(code: URL? = nil) {
        if let code, let receiving = receivingTransfer, receiving.screen != nil {
            receiving.model.use(code)
            return
        }
        let model = model
        let device = UIDevice.current.name
        let receiving = TransferReceiving(code: code) { [weak self] code, progress in
            guard let invitation = TransferInvitation(url: code) else { throw TransferReceiver.Failure.unexpected }
            let payload = try await TransferNetwork.receive(invitation, as: device) {
                await progress(.connected)
            }
            let added = try await model.addTransferred(payload)
            // A device that had no account shows the mail under the screen, ready when it closes.
            if let self, case .welcome = screen, !model.accounts.isEmpty { showMailbox() }
            return added
        }
        let screen = TransferReceiveScreen.make(model: receiving)
        receivingTransfer = ReceivingTransfer(screen: screen, model: receiving)
        topViewController()?.present(screen, animated: true)
    }

    /// Face ID, Touch ID or the passcode. A device with none set has nothing to ask for.
    private nonisolated static func unlockAsOwner() async -> Bool {
        let context = LAContext()
        // Unsafe because the error out-parameter is a pointer. Safe: passing nil hands it no pointer at all.
        guard unsafe context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { return true }
        return
            (try? await context.evaluatePolicy(
                .deviceOwnerAuthentication, localizedReason: TransferSending.unlockReason))
            ?? false
    }
}

/// The screen receiving accounts, and what it receives with. It's up as long as UIKit keeps `screen`.
struct ReceivingTransfer {
    weak var screen: UIViewController?
    let model: TransferReceiving
}
