import MailCore
import MailUI
import UIKit

/// The window's side of sharing accounts with the reader's other devices: it shows the accounts another device
/// added or removed, and offers the ones this device doesn't have yet.
extension SceneCoordinator {
    func observeSharedAccounts() {
        deviceObservers.append(
            NotificationCenter.default.addObserver(
                forName: AppModel.sharedAccountsDidUpdate, object: model, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.followSharedAccounts() }
            })
    }

    private func followSharedAccounts() {
        switch screen {
        case .starting, .offer:
            // Not started yet, or the offer in place of the welcome screen decides what follows once answered.
            return
        case .welcome:
            if !model.accounts.isEmpty { showMailbox() }
        case .mailbox(_, _, .settings):
            // Closing Settings follows whatever changed meanwhile, and makes the offer.
            return
        case .mailbox(_, let accounts, _), .message(_, let accounts):
            if model.accounts.isEmpty {
                showWelcome()
            } else if accounts != model.accounts.map(\.id) {
                showMailboxKeepingPlace()
            }
        }
        offerSharedAccounts()
    }

    /// Offers the accounts in `AppModel.accountOffer`: in place of the welcome screen on a device with none, or as a sheet over
    /// the mail screens of the key window. One offer at a time; answering it, either way, stops it coming back on its
    /// own.
    func offerSharedAccounts() {
        guard let offered = model.accountOffer else { return }
        let offer = SharedAccountsOffer(
            accounts: offered.accounts, origin: offered.origin,
            add: { [model] in try await model.addOfferedAccounts($0, declining: $1) },
            decline: { Preferences.declinedSharedAccounts.formUnion($0) })
        let sheet = SharedAccountsOfferScreen.make(offer: offer)
        switch screen {
        case .starting, .welcome:
            offer.onFinished = { [weak self] in
                guard let self else { return }
                model.accounts.isEmpty ? showWelcome() : showMailbox()
            }
            enter(.offer(sheet))
        case .mailbox(let split, let accounts, .none) where window.isKeyWindow:
            // Not Now is the way out, so the choice is remembered.
            sheet.isModalInPresentation = true
            offer.onFinished = { [weak self] in self?.offerAnswered() }
            enter(.mailbox(split, accounts: accounts, cover: .offer(sheet)))
            topViewController()?.present(sheet, animated: true)
        case .offer, .mailbox, .message:
            return
        }
    }

    /// The sheet over the mail screens was answered and closes itself.
    private func offerAnswered() {
        guard case .mailbox(let split, let accounts, .offer) = screen else { return }
        enter(.mailbox(split, accounts: accounts, cover: .none))
    }
}
