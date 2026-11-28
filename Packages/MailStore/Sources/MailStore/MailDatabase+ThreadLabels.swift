public import MailCore

extension MailFollowing {
    /// The labels `thread` carries as sync and local changes leave its row, which say which mailboxes hold it; `nil`
    /// while it isn't on the device. Its messages' own labels change only when they are fetched again, so they can't
    /// tell a reader that another device archived it. Emits now and after every change.
    public func labels(ofThread thread: ThreadSummary.ID) -> AsyncThrowingStream<Set<String>?, any Error> {
        followed.observe { db in try MailDatabase.thread(thread, in: db)?.labelIDs }
    }
}
