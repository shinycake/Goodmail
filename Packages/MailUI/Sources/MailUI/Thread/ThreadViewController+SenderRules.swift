import MailCore
import UIKit

extension ThreadViewModel {
    /// The reader's own addresses on the thread's account.
    var ownAddresses: [String] { [accountEmail] + accountAliases.map(\.address) }

    /// Who the conversation is from, for Block Sender and VIPs: the sender of its newest message someone else sent,
    /// or its list row's sender while its messages load. `nil` for a conversation of only the reader's mail.
    var sender: SenderAddress? {
        let own = ownAddresses
        let newest = messages.last { SenderAddress(of: $0.from, notFrom: own) != nil }?.from ?? thread.sender
        return SenderAddress(of: newest, notFrom: own)
    }

    func senderAnswer(to command: MailCommand) -> CommandAnswer? {
        senders?.answer(to: command, for: [thread.id], from: sender)
    }
}

/// A sender's address or picture in the conversation offers Apply Rules, the VIP command and Block Sender for that
/// person, as Mail offers Block Sender on an address.
extension ThreadViewController: SenderMenuOffering {
    func senderMenu(for contact: Contact) -> UIMenu? {
        let model = viewModel
        guard let senders = model.senders else { return nil }
        return senders.menuSection(
            for: [model.thread.id], from: SenderAddress(of: contact, notFrom: model.ownAddresses))
    }
}
