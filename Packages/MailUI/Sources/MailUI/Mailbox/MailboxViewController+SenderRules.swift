import MailCore
import UIKit

extension MailboxViewController {
    /// Apply Rules, Block Sender and the VIP command for the picked threads, dimmed with none picked. A thread on show
    /// answers them first, for itself.
    func senderAnswer(to command: MailCommand) -> CommandAnswer? {
        guard let senders = viewModel.senders, let actions = viewModel.actions else { return nil }
        let ids = selectedIDs
        // The rows share the sender the commands are for, so Block Sender takes every one of them away.
        let sender = viewModel.sender(of: ids)
        return actions.senderAnswer(to: command, for: ids, from: sender, conversationsFrom: sender, with: senders)
    }
}

extension ThreadMenu.Elements {
    /// The sender's commands for the threads the menu is for, where the app offers them.
    var senderSection: UIMenu? {
        guard let viewModel, let senders = viewModel.senders, let actions = viewModel.actions else { return nil }
        let sender = viewModel.sender(of: ids)
        return actions.senderMenuSection(for: ids, from: sender, conversationsFrom: sender, with: senders)
    }
}
