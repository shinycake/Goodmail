import GRDB
public import MailCore

/// The lists of the reader's own a window can show, which a window restored or handed off on one deleted since, or
/// not synced here yet, follows (`WindowState.ListCheck`).
extension MailDatabase {
    /// Every label of every account and every smart mailbox, now and after each change to them.
    public func ownLists() -> AsyncThrowingStream<WindowState.OwnLists, any Error> {
        observe { db in
            let labels = try LabelRecord.fetchAll(db).map {
                Mailbox(labelID: $0.id, accountID: AccountID(rawValue: $0.accountID))
            }
            return WindowState.OwnLists(
                labels: Set(labels), smartMailboxes: Set(try Self.smartMailboxes(db).map(\.id)))
        }
    }
}
