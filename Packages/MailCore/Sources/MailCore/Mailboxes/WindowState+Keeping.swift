extension WindowState {
    /// The lists of the reader's own that a window can show: the labels and smart mailboxes on the device now.
    public struct OwnLists: Equatable, Sendable {
        /// Every label of every account, standard or the reader's own, as the mailbox it lists.
        public var labels: Set<Mailbox>
        public var smartMailboxes: Set<SmartMailbox.ID>

        public init(labels: Set<Mailbox>, smartMailboxes: Set<SmartMailbox.ID>) {
            self.labels = labels
            self.smartMailboxes = smartMailboxes
        }
    }

    /// This state without what belongs to accounts outside `accounts`, as when a window is restored after one was
    /// removed: an account's own mailbox gives way to the Inbox, and a conversation of a gone account closes.
    public func keeping(_ accounts: [AccountID]) -> WindowState {
        var kept = self
        if case .mailbox(let mailbox) = list, let account = mailbox.accountID, !accounts.contains(account) {
            kept.list = WindowState().list
        }
        if let reading, !accounts.contains(reading.thread.accountID) { kept.closeReader() }
        return kept
    }

    /// This state without what is gone from the device: as `keeping(_:)`, and a deleted label or smart mailbox gives
    /// way to the Inbox. A conversation read in a deleted label reads on in All Mail.
    public func keeping(_ accounts: [AccountID], lists: OwnLists) -> WindowState {
        var kept = keeping(accounts)
        if !lists.holds(kept.list) { kept.list = WindowState().list }
        if let reading = kept.reading, !lists.holds(reading.mailbox) {
            kept.read(Reading(reading.thread, in: .allMail))
        }
        return kept
    }
}

extension WindowState.OwnLists {
    /// Whether `mailbox` is still there: a standard one always is, a label of the reader's own while it exists.
    fileprivate func holds(_ mailbox: Mailbox) -> Bool {
        mailbox.isStandard || labels.contains(mailbox)
    }

    fileprivate func holds(_ list: WindowState.List) -> Bool {
        switch list {
        case .mailbox(let mailbox): holds(mailbox)
        case .smart(let id): smartMailboxes.contains(id)
        case .scheduled, .snoozed: true
        }
    }
}
