import GRDB
public import MailCore

extension MailDatabase {
    /// The conversations with a downloaded message that carries files, not counting the pictures its body shows
    /// inline. A conversation whose messages were never downloaded can't be known to, so it isn't here. Emits now and
    /// after every change, which reads every stored message, so it is followed only while a list filters by it.
    public func threadsHoldingAttachments() -> AsyncThrowingStream<Set<ThreadSummary.ID>, any Error> {
        observe { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT DISTINCT message.accountID, message.threadID FROM message
                    WHERE EXISTS (
                        SELECT 1 FROM json_each(message.content, '$.attachments') AS file
                        WHERE json_extract(file.value, '$.isInline') = 0)
                    """)
            return Set(
                rows.map { row in
                    ThreadSummary.ID(accountID: AccountID(rawValue: row["accountID"]), threadID: row["threadID"])
                })
        }
    }
}
