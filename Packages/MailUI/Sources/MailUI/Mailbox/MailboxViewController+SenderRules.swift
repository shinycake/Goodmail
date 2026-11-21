import MailCore
import UIKit

extension MailboxViewController {
    /// Apply Rules, Block Sender and the VIP command for the picked threads, dimmed with none picked. A thread on show
    /// answers them first, for itself.
    func senderAnswer(to command: MailCommand) -> CommandAnswer? {
        guard let senders = viewModel.senders else { return nil }
        let ids = selectedIDs
        return senders.answer(to: command, for: ids, from: viewModel.sender(of: ids), in: viewModel.actions)
    }
}

extension ThreadMenu.Elements {
    /// The sender's commands for the threads the menu is for, where the app offers them.
    var senderSection: UIMenu? {
        guard let viewModel, let senders = viewModel.senders else { return nil }
        return senders.menuSection(for: ids, from: viewModel.sender(of: ids), in: viewModel.actions)
    }
}
