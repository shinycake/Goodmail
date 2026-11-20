import LocalAuthentication
import MailCore
import MailUI
import UIKit
import os

/// The screens that move accounts between devices by QR code, for a mail window or the Settings window to present.
enum TransferScreens {
    /// Shows a code for another device to scan, and sends it the accounts the reader picks.
    static func sending(_ model: AppModel) -> UIViewController {
        let accounts = model.accounts
        let sending = TransferSending(
            accounts: accounts, unlock: { await unlockAsOwner() },
            host: {
                let host = TransferHost { try await AppModel.transferPayload(of: accounts, chosen: $0) }
                #if DEBUG
                    // A simulator can't scan, so testing a transfer between two opens this code on the other.
                    Logger.sharing.debug("Transfer code: \(host.code, privacy: .public)")
                #endif
                return host
            })
        return TransferSendScreen.make(model: sending)
    }

    /// Scans another device's code, or receives from `code` when the Camera app already scanned it. `added` runs once
    /// the accounts it brought are on this device.
    static func receiving(
        _ model: AppModel, code: URL? = nil, added: @escaping () -> Void = {}
    ) -> (screen: UIViewController, model: TransferReceiving) {
        let device = UIDevice.current.name
        let receiving = TransferReceiving(code: code) { code, progress in
            guard let invitation = TransferInvitation(url: code) else { throw TransferReceiver.Failure.unexpected }
            let payload = try await TransferNetwork.receive(invitation, as: device) {
                await progress(.connected)
            }
            let accounts = try await model.addTransferred(payload)
            added()
            return accounts
        }
        return (TransferReceiveScreen.make(model: receiving), receiving)
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
