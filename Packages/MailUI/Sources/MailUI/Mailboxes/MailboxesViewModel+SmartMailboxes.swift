import MailCore

/// The Smart Mailboxes section: the reader's saved searches, after the standard mailboxes and before the accounts'
/// own (ADR-039).
extension MailboxesViewModel {
    /// One row for each box, in the reader's order, counting its unread conversations.
    var smartGroup: Group {
        Group(
            section: .smartMailboxes,
            items: smartDirectory.mailboxes.map { box in
                let unread = smartDirectory.unreadCounts[box.id] ?? 0
                return Item(
                    destination: .smart(box.id), title: box.title, symbol: box.symbol, count: unread,
                    nestedCount: unread, color: nil)
            })
    }

    /// The smart mailbox a row shows.
    func smartMailbox(at destination: Destination) -> SmartMailbox? {
        guard case .smart(let id) = destination else { return nil }
        return smartDirectory.mailboxes.first { $0.id == id }
    }

    /// Opens the editor on the box.
    func edit(_ box: SmartMailbox) {
        navigate(.editSmartMailbox(box.id))
    }

    /// Opens the editor on a new box.
    func newSmartMailbox() {
        navigate(.newSmartMailbox(SearchQuery(terms: [])))
    }
}
