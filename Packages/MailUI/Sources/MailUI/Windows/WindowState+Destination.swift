public import MailCore

extension WindowState {
    /// Where the mailboxes list marks the reader as being: the row of the list the window shows.
    public var destination: MailboxesViewModel.Destination {
        switch list {
        case .mailbox(let mailbox): .mailbox(mailbox)
        case .scheduled: .scheduled
        case .snoozed: .snoozed
        case .smart(let id): .smart(id)
        }
    }
}
