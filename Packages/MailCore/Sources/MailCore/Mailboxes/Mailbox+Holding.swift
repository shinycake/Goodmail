extension Mailbox {
    /// The one standard mailbox a message or conversation carrying `labels` is in: Trash and Spam hold it alone, then
    /// Drafts, the Inbox and Sent, or else All Mail.
    public static func holding(_ labels: Set<String>) -> Mailbox {
        let order = [SystemLabel.trash, SystemLabel.spam, SystemLabel.draft, SystemLabel.inbox, SystemLabel.sent]
        return order.first(where: labels.contains).map { Mailbox(labelID: $0) } ?? .allMail
    }

    /// Whether this is one of the mailboxes every account has, in every account or in one, rather than a label of the
    /// reader's own, which can be deleted.
    public var isStandard: Bool {
        Mailbox.standard.contains { $0.labelID == labelID }
    }
}
