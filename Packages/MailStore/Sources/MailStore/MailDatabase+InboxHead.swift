import GRDB
public import MailCore

/// A device that keeps only the head of the Inbox (`SyncScope.inboxHead`) drops the threads that left it.
extension MailDatabase {
    /// Deletes the account's threads that aren't in the Inbox, with their messages, except a thread that still has
    /// work queued on the device: an intent in the outbox or a reply waiting to send. Returns how many it deleted.
    @discardableResult
    public func pruneOutsideInbox(account: AccountID) throws -> Int {
        try write { db in
            try db.execute(
                sql: """
                    DELETE FROM thread
                    WHERE accountID = ?
                    AND NOT EXISTS (
                        SELECT 1 FROM threadLabel
                        WHERE threadLabel.accountID = thread.accountID AND threadLabel.threadID = thread.id
                        AND threadLabel.labelID = 'INBOX')
                    AND NOT EXISTS (
                        SELECT 1 FROM outbox WHERE outbox.accountID = thread.accountID AND outbox.threadID = thread.id)
                    AND NOT EXISTS (
                        SELECT 1 FROM outgoing
                        WHERE outgoing.accountID = thread.accountID
                        AND json_extract(outgoing.draft, '$.threadID') = thread.id)
                    """,
                arguments: [account.rawValue])
            return db.changesCount
        }
    }
}
