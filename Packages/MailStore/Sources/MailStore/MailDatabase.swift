public import Foundation
import GRDB

/// The shared mail database. The app and the Notification Service Extension both write to it (ADR-002),
/// so every write is a short transaction and every process waits out the other's lock.
public final class MailDatabase: Sendable {
    let pool: DatabasePool
    /// Tells both processes the mail changed; `write` posts it. Internal for writes that change nothing most times.
    let signal: ChangeSignal
    /// Re-checks when the process resumes, for the other processes' writes heard while suspended.
    private let resumed: ObservationRecheck

    /// Opens (creating if needed) the database at `url` and migrates it to the current schema.
    public init(url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // The NSE opens the database while the phone is locked; files created here inherit this class.
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: directory.path
        )

        var configuration = Configuration()
        configuration.busyMode = .timeout(5)
        // So `suspendAll()` can release the locks before iOS suspends the process (0xdead10cc).
        configuration.observesSuspensionNotifications = true
        let pool = try DatabasePool(path: url.path, configuration: configuration)
        try Self.migrator.migrate(pool)
        try Self.fillMessageText(in: pool)
        self.pool = pool
        // Another process wrote: re-run this process's observations against the new data. On the writer's queue, so
        // a resume on the main actor doesn't wait for the lock. While suspended it fails, and `resumed` re-checks.
        let recheck: @Sendable () -> Void = {
            pool.asyncWrite({ db in try db.notifyChanges(in: .fullDatabase) }, completion: { _, _ in })
        }
        signal = ChangeSignal(onForeignChange: recheck)
        resumed = ObservationRecheck(recheck)
    }

    /// Every write goes through here, so the other processes hear about it.
    func write<T>(_ updates: (Database) throws -> T) throws -> T {
        let result = try pool.write(updates)
        signal.post()
        return result
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1-accounts") { db in
            try db.create(table: "account") { table in
                table.primaryKey("id", .text)
                table.column("email", .text).notNull().unique()
                table.column("color", .text).notNull()
                table.column("createdAt", .datetime).notNull()
            }
        }
        migrator.registerMigration("v2-threads") { db in
            try db.create(table: "thread") { table in
                table.column("accountID", .text).notNull().references("account", onDelete: .cascade)
                table.column("id", .text).notNull()
                table.column("subject", .text).notNull()
                table.column("snippet", .text).notNull()
                table.column("senderName", .text)
                table.column("senderAddress", .text).notNull()
                table.column("date", .datetime).notNull()
                table.column("isUnread", .boolean).notNull()
                table.column("messageCount", .integer).notNull()
                table.primaryKey(["accountID", "id"])
            }
            // Gmail labels are many-to-many; folder providers will map each folder to one label row.
            try db.create(table: "threadLabel") { table in
                table.column("accountID", .text).notNull()
                table.column("threadID", .text).notNull()
                table.column("labelID", .text).notNull()
                table.primaryKey(["accountID", "threadID", "labelID"])
                table.foreignKey(["accountID", "threadID"], references: "thread", onDelete: .cascade)
            }
            try db.create(index: "threadLabel_byLabel", on: "threadLabel", columns: ["labelID", "accountID"])
            try db.create(index: "thread_byDate", on: "thread", columns: ["date"])
        }
        migrator.registerMigration("v3-sync") { db in
            // The resync that last saw the thread; see `Sweep`.
            try db.alter(table: "thread") { table in
                table.add(column: "generation", .integer).notNull().defaults(to: 0)
            }
            try db.create(table: "label") { table in
                table.column("accountID", .text).notNull().references("account", onDelete: .cascade)
                table.column("id", .text).notNull()
                table.column("name", .text).notNull()
                table.column("kind", .text).notNull()
                table.column("color", .text)
                table.column("isHidden", .boolean).notNull()
                table.primaryKey(["accountID", "id"])
            }
            try db.create(table: "syncState") { table in
                table.primaryKey("accountID", .text).references("account", onDelete: .cascade)
                table.column("state", .jsonText).notNull()
            }
        }
        migrator.registerMigration("v4-messages") { db in
            // Bodies are cached per thread and go with it (ADR-007).
            try db.create(table: "message") { table in
                table.column("accountID", .text).notNull()
                table.column("id", .text).notNull()
                table.column("threadID", .text).notNull()
                table.column("date", .datetime).notNull()
                table.column("content", .jsonText).notNull()
                table.column("fetchedAt", .datetime).notNull()
                table.primaryKey(["accountID", "id"])
                table.foreignKey(["accountID", "threadID"], references: "thread", onDelete: .cascade)
            }
            try db.create(index: "message_byThread", on: "message", columns: ["accountID", "threadID", "date"])
        }
        migrator.registerMigration("v5-outbox") { db in
            // Not tied to the thread: an intent outlives a sweep that removes its thread, and is dropped on replay.
            try db.create(table: "outbox") { table in
                table.autoIncrementedPrimaryKey("sequence")
                table.column("id", .text).notNull().unique()
                table.column("accountID", .text).notNull()
                table.column("threadID", .text).notNull()
                table.column("intent", .jsonText).notNull()
            }
            try db.create(index: "outbox_byThread", on: "outbox", columns: ["accountID", "threadID"])
        }
        migrator.registerMigration("v6-outbox-sent") { db in
            try db.alter(table: "outbox") { table in
                table.add(column: "sentAt", .datetime)
            }
        }
        migrator.registerMigration("v7-outgoing") { db in
            try db.create(table: "outgoing") { table in
                table.column("id", .text).primaryKey()
                table.column("accountID", .text).notNull()
                table.column("sendAt", .datetime).notNull()
                table.column("failure", .text)
                table.column("draft", .jsonText).notNull()
            }
        }
        migrator.registerMigration("v8-search") { db in
            // Kept in step with `thread` by triggers. Bodies aren't indexed: most mail is never opened here.
            try db.create(virtualTable: "threadSearch", using: FTS5()) { table in
                table.synchronize(withTable: "thread")
                table.tokenizer = .unicode61()
                table.column("subject")
                table.column("senderName")
                table.column("senderAddress")
                table.column("snippet")
            }
        }
        migrator.registerMigration("v9-signature") { db in
            try db.alter(table: "account") { table in table.add(column: "signature", .text) }
        }
        migrator.registerMigration("v10-outgoing-purpose") { db in
            try db.alter(table: "outgoing") { table in
                table.add(column: "purpose", .text).notNull().defaults(to: "send")
            }
        }
        migrator.registerMigration("v11-address-book") { db in
            try db.create(table: "addressBook") { table in
                table.column("accountID", .text).notNull().references("account", onDelete: .cascade)
                table.column("address", .text).notNull().collate(.nocase)
                table.column("name", .text)
                table.column("fetchedAt", .datetime).notNull()
                table.primaryKey(["accountID", "address"])
            }
        }
        migrator.registerMigration("v12-message-search") { db in
            // The words of each cached body, drawn from it as it is saved. NULL until then: bodies cached before
            // this migration get theirs from `fillMessageText` on open, which the partial index finds quickly.
            try db.alter(table: "message") { table in table.add(column: "bodyText", .text) }
            try db.execute(sql: "CREATE INDEX message_withoutText ON message(accountID) WHERE bodyText IS NULL")
            // Kept in step with `message` by triggers, so a thread's bodies leave the index with it.
            try db.create(virtualTable: "messageSearch", using: FTS5()) { table in
                table.synchronize(withTable: "message")
                table.tokenizer = .unicode61()
                table.column("bodyText")
            }
        }
        migrator.registerMigration("v13-cache-cap") { db in
            // What each cached body weighs (its JSON and its search text, in bytes) and when its thread was last
            // read, which the cache cap evicts by. Bodies cached before this count as read when fetched.
            try db.alter(table: "message") { table in
                table.add(column: "size", .integer).notNull().defaults(to: 0)
                table.add(column: "accessedAt", .datetime)
            }
            try db.execute(
                sql: """
                    UPDATE message
                    SET size = length(CAST(content AS BLOB)) + length(CAST(COALESCE(bodyText, '') AS BLOB)),
                        accessedAt = fetchedAt
                    """)
        }
        migrator.registerMigration("v14-account-service") { db in
            // Every account added before this was a Gmail account.
            try db.alter(table: "account") { table in
                table.add(column: "service", .text).notNull().defaults(to: "gmail")
            }
        }
        migrator.registerMigration("v15-account-name") { db in
            try db.alter(table: "account") { table in table.add(column: "name", .text) }
        }
        migrator.registerMigration("v16-message-index") { db in
            // Which thread each message belongs to, for providers whose changes name messages (MessageIndexStore).
            try db.create(table: "messageIndex") { table in
                table.column("accountID", .text).notNull().references("account", onDelete: .cascade)
                table.column("key", .text).notNull()
                table.column("threadID", .text).notNull()
                table.column("internetMessageID", .text)
                table.primaryKey(["accountID", "key"])
            }
            try db.create(index: "messageIndex_thread", on: "messageIndex", columns: ["accountID", "threadID"])
            try db.create(
                index: "messageIndex_internetMessageID", on: "messageIndex",
                columns: ["accountID", "internetMessageID"])
        }
        migrator.registerMigration("v17-snooze") { db in
            // One row per snoozed thread: asleep until `wakeAt`, or woken at `wokeAt` once that is set.
            try db.create(table: "snooze") { table in
                table.column("accountID", .text).notNull().references("account", onDelete: .cascade)
                table.column("threadID", .text).notNull()
                table.column("wakeAt", .datetime)
                table.column("wokeAt", .datetime)
                table.primaryKey(["accountID", "threadID"])
                table.check(sql: "(wakeAt IS NULL) != (wokeAt IS NULL)")
            }
            try db.create(index: "snooze_byWake", on: "snooze", columns: ["wakeAt"])
        }
        migrator.registerMigration("v18-outgoing-upload") { db in
            // The upload a message was handed to (see `OutgoingMessage.Delivery`), and failures as a kind rather
            // than English text, so the app can word them in the reader's language.
            try db.alter(table: "outgoing") { table in table.add(column: "upload", .text) }
            try db.execute(
                sql: """
                    UPDATE outgoing SET failure = CASE
                        WHEN failure IN ('A forwarded attachment is no longer available.', 'forwardedAttachmentMissing')
                            THEN 'forwardedAttachmentMissing'
                        ELSE 'rejected' END
                    WHERE failure IS NOT NULL
                    """)
        }
        // Shares v18 with the upload migration because TestFlight builds ran it under this name before that one existed.
        migrator.registerMigration("v18-notifications") { db in
            // Each account's alert choice and how far its mail has been considered (AccountNotifications).
            try db.create(table: "notificationSettings") { table in
                table.primaryKey("accountID", .text).references("account", onDelete: .cascade)
                table.column("level", .text).notNull()
                table.column("seenThrough", .datetime).notNull()
            }
            // What the push relay and the service know about the account's pushes to this device.
            try db.create(table: "pushSubscription") { table in
                table.primaryKey("accountID", .text).references("account", onDelete: .cascade)
                table.column("deviceToken", .text).notNull()
                table.column("registeredAt", .datetime).notNull()
                table.column("watchExpiresAt", .datetime).notNull()
            }
        }
        migrator.registerMigration("v19-push-channel") { db in
            // Subscriptions now say how the service reaches the relay (PushChannel). The rows are only a cache of
            // what the relay holds, so they are dropped and each account subscribes again on the next launch.
            try db.drop(table: "pushSubscription")
            try db.create(table: "pushSubscription") { table in
                table.primaryKey("accountID", .text).references("account", onDelete: .cascade)
                table.column("deviceToken", .text).notNull()
                table.column("environment", .text).notNull()
                table.column("channel", .text).notNull()
                table.column("renewedAt", .datetime).notNull()
                table.column("expiresAt", .datetime).notNull()
            }
        }
        migrator.registerMigration("v20-badge") { db in
            // Each account's choice of what counts toward the app badge (BadgeSource). No row counts the Inbox.
            try db.create(table: "badgeSettings") { table in
                table.primaryKey("accountID", .text).references("account", onDelete: .cascade)
                table.column("source", .text).notNull()
            }
        }
        migrator.registerMigration("v21-pins") { db in
            // One row per pinned thread. Tied to the account, not the thread: a sweep may drop a thread that comes
            // back, and it comes back pinned.
            try db.create(table: "pin") { table in
                table.column("accountID", .text).notNull().references("account", onDelete: .cascade)
                table.column("threadID", .text).notNull()
                table.primaryKey(["accountID", "threadID"])
            }
        }
        migrator.registerMigration("v22-device-mutes") { db in
            // Threads muted on the device, for services without Mute (`MailService.mutesOnDevice`), with the date of
            // the newest message the mute has seen: a newer one is a reply, kept out of the Inbox.
            try db.create(table: "deviceMute") { table in
                table.column("accountID", .text).notNull().references("account", onDelete: .cascade)
                table.column("threadID", .text).notNull()
                table.column("mutedThrough", .datetime).notNull()
                table.primaryKey(["accountID", "threadID"])
            }
        }
        migrator.registerMigration("v23-aliases") { db in
            // The other addresses each account sends as (Account.aliases), as JSON; none until the next sync.
            try db.alter(table: "account") { table in table.add(column: "aliases", .text).notNull().defaults(to: "[]") }
        }
        migrator.registerMigration("v24-saved-draft-copies") { db in
            // The provider's copy of each draft the device saved, by the draft's own ID, so saving it again as it
            // is written replaces that copy rather than adding one.
            try db.create(table: "savedDraftCopy") { table in
                table.primaryKey("draftID", .text)
                table.column("accountID", .text).notNull().references("account", onDelete: .cascade)
                table.column("messageID", .text).notNull()
            }
        }
        migrator.registerMigration("v25-contact-photos") { db in
            try db.alter(table: "addressBook") { table in table.add(column: "photoURL", .text) }
            // Senders' photos are looked up by address alone, across the accounts.
            try db.execute(sql: "CREATE INDEX addressBookPhoto ON addressBook (address) WHERE photoURL IS NOT NULL")
            // Address books fetched before photos were read are fetched again on the next sync.
            try db.execute(sql: "UPDATE addressBook SET fetchedAt = ?", arguments: [Date.distantPast])
        }
        migrator.registerMigration("v26-account-order") { db in
            // Where each account stands among the others, which the reader can change. Until now that was the order
            // they were added in, so that is where each one starts.
            try db.alter(table: "account") { table in table.add(column: "position", .integer).notNull().defaults(to: 0)
            }
            try db.execute(
                sql: """
                    UPDATE account SET position = (
                        SELECT COUNT(*) FROM account AS earlier
                        WHERE earlier.createdAt < account.createdAt
                            OR (earlier.createdAt = account.createdAt AND earlier.id < account.id))
                    """)
        }
        migrator.registerMigration("v27-rules") { db in
            // The reader's rules (`MailRule`), as JSON, in the order they run.
            try db.create(table: "mailRule") { table in
                table.primaryKey("id", .text)
                table.column("position", .integer).notNull()
                table.column("json", .text).notNull()
            }
            // How far each account's arrived mail has been through the rules: threads newer than `through` haven't.
            try db.create(table: "ruleProgress") { table in
                table.primaryKey("accountID", .text).references("account", onDelete: .cascade)
                table.column("through", .datetime).notNull()
            }
        }
        migrator.registerMigration("v28-focus") { db in
            // Whether the current Focus filter shows the account in the blended views (FocusFilter).
            try db.alter(table: "account") { table in
                table.add(column: "inFocus", .boolean).notNull().defaults(to: true)
            }
        }
        migrator.registerMigration("v29-imap-snippets") { db in
            // IMAP snippets stored until now could be the CSS at the top of an HTML mail. Filling each IMAP account's
            // window again, as after an expired cursor, stores every thread's snippet anew.
            try db.execute(
                sql:
                    "DELETE FROM syncState WHERE accountID IN (SELECT id FROM account WHERE service IN ('icloud', 'imap'))"
            )
        }
        migrator.registerMigration("v30-minimized-drafts") { db in
            // The messages minimized at the bottom of each window, as written, in order (`draft` is a Draft as JSON).
            try db.create(table: "minimizedDraft") { table in
                table.primaryKey("draftID", .text)
                table.column("window", .text).notNull()
                table.column("position", .integer).notNull()
                table.column("accountID", .text).notNull().references("account", onDelete: .cascade)
                table.column("draft", .text).notNull()
            }
        }
        migrator.registerMigration("v31-account-nicknames") { db in
            // What the reader calls each account (Account.nickname); none until they name it.
            try db.alter(table: "account") { table in table.add(column: "nickname", .text) }
        }
        migrator.registerMigration("v32-watch-token") { db in
            // The paired watch's APNs token each subscription was registered with (DeviceToken.watch, ADR-023).
            try db.alter(table: "pushSubscription") { table in table.add(column: "watchToken", .text) }
        }
        migrator.registerMigration("v33-snippet-filler") { db in
            // Snippets stored until now could hold a marketing mail's invisible preheader filler, or for IMAP that
            // filler read as Latin-1.
            try repairSnippets(db)
        }
        migrator.registerMigration("v34-snooze-keeper") { db in
            // Which device answers for an asleep thread's wake (SnoozeKeeper, ADR-037); none once it woke. Every
            // snooze until now was made on this device.
            try db.alter(table: "snooze") { table in table.add(column: "keeper", .text) }
            try db.execute(sql: "UPDATE snooze SET keeper = 'thisDevice' WHERE wakeAt IS NOT NULL")
        }
        migrator.registerMigration("v35-vips", migrate: createVIPs)
        migrator.registerMigration("v36-smart-mailboxes", migrate: createSmartMailboxes)
        return migrator
    }
}
