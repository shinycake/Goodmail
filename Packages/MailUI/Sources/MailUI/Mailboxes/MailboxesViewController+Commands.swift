public import MailCore
import UIKit

/// The mailboxes make a new label from the menu bar, Mail's New Mailbox, as the New Label button below them does.
extension MailboxesViewController: CommandScreen {
    public func answer(to command: MailCommand) -> CommandAnswer {
        switch command {
        case .newLabel:
            let accounts = viewModel.labelAccounts
            guard !accounts.isEmpty else { return .unavailable }
            return .ready(perform: { [weak self] in self?.newLabel(in: accounts) })
        default:
            return .notHere
        }
    }

    /// Asks for the new label's name, and with several accounts first which one it goes in, as the button's menu does.
    private func newLabel(in accounts: [Account]) {
        guard accounts.count > 1 else {
            accounts.first.flatMap { labelFlow(for: $0.id) }?.create { _ in }
            return
        }
        let alert = UIAlertController(title: LabelEditFlow.newLabel, message: nil, preferredStyle: .alert)
        for account in accounts {
            alert.addAction(
                UIAlertAction(title: account.title, style: .default) { [weak self] _ in
                    self?.labelFlow(for: account.id)?.create { _ in }
                })
        }
        alert.addAction(UIAlertAction(title: LabelEditFlow.cancel, style: .cancel))
        present(alert, animated: true)
    }
}
