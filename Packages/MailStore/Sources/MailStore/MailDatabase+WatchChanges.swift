public import Foundation
import GRDB
public import MailCore

/// A change the reader made on the watch to an account it reads itself (ADR-023), kept until it settles, so that
/// turning "Mail Without iPhone" off can give back what didn't go even after the app was quit meanwhile. Only the
/// watch keeps these.
public struct WatchChange: Equatable, Sendable {
    public let id: UUID
    /// The reader's command, as the watch encoded it.
    public let command: Data
    /// The replies it queued, in the order it queued them.
    public let drafts: [Draft.ID]
    /// Whether any intent it queued (`OutboxIntent.origin`) is still unsent.
    public let queued: Bool

    public init(id: UUID, command: Data, drafts: [Draft.ID] = [], queued: Bool = false) {
        self.id = id
        self.command = command
        self.drafts = drafts
        self.queued = queued
    }
}

extension MailDatabase {
    /// Keeps `command`, the change `id`, before it is made. Keeping it again changes nothing.
    public func keepWatchChange(_ id: UUID, command: Data) throws {
        try write { db in
            try db.execute(
                sql: "INSERT OR IGNORE INTO watchChange (id, command) VALUES (?, ?)",
                arguments: [id.uuidString, command])
        }
    }

    /// Notes that the change `id` queues the reply `draft`, before the reply is queued.
    public func addDraft(_ draft: Draft.ID, toWatchChange id: UUID) throws {
        try write { db in
            try db.execute(
                sql: "INSERT OR IGNORE INTO watchChangeDraft (change, draft) VALUES (?, ?)",
                arguments: [id.uuidString, draft.uuidString])
        }
    }

    /// Every change kept, in the order they were kept.
    public func watchChanges() throws -> [WatchChange] {
        try read { db in
            let drafts = try Row.fetchAll(db, sql: "SELECT change, draft FROM watchChangeDraft ORDER BY rowid")
                .reduce(into: [String: [Draft.ID]]()) { drafts, row in
                    if let draft = UUID(uuidString: row["draft"]) { drafts[row["change"], default: []].append(draft) }
                }
            return try Row.fetchAll(
                db,
                sql: """
                    SELECT id, command, EXISTS (
                        SELECT 1 FROM outbox WHERE origin = watchChange.id AND sentAt IS NULL
                    ) AS queued
                    FROM watchChange ORDER BY rowid
                    """
            ).compactMap { row in
                let key: String = row["id"]
                guard let id = UUID(uuidString: key) else { return nil }
                return WatchChange(id: id, command: row["command"], drafts: drafts[key] ?? [], queued: row["queued"])
            }
        }
    }

    /// Lets go of the change `id`, settled now.
    public func removeWatchChange(_ id: UUID) throws {
        try write { db in try Self.removeWatchChanges([id.uuidString], in: db) }
    }

    /// Lets go of every change that has nothing left on its way, no unsent intent and no reply queued or uploading,
    /// except the changes `making`, which may not have queued theirs yet.
    public func removeSettledWatchChanges(except making: Set<UUID>) throws {
        try write { db in
            let settled = try String.fetchAll(
                db,
                sql: """
                    SELECT id FROM watchChange WHERE NOT EXISTS (
                        SELECT 1 FROM outbox WHERE origin = watchChange.id AND sentAt IS NULL
                    ) AND NOT EXISTS (
                        SELECT 1 FROM watchChangeDraft JOIN outgoing ON outgoing.id = watchChangeDraft.draft
                        WHERE watchChangeDraft.change = watchChange.id
                    )
                    """)
            let kept = Set(making.map(\.uuidString))
            try Self.removeWatchChanges(settled.filter { !kept.contains($0) }, in: db)
        }
    }

    /// Hands the watch's changes over, in one transaction: keeps `handbacks` for the iPhone until they are
    /// delivered (`watchHandbacks`), lets go of the changes `changes`, and forgets each account's sync as
    /// `forgetSync` does, so nothing given back can still go from the watch.
    public func handOver(_ handbacks: [Data], changes: some Collection<UUID>) throws {
        try write { db in
            for handback in handbacks {
                try db.execute(sql: "INSERT INTO watchHandback (handback) VALUES (?)", arguments: [handback])
            }
            try Self.removeWatchChanges(changes.map(\.uuidString), in: db)
            for account in try String.fetchAll(db, sql: "SELECT id FROM account") {
                try Self.forgetSync(of: account, in: db)
            }
        }
    }

    /// The handbacks not yet delivered, oldest first, each with its place to remove it by.
    public func watchHandbacks() throws -> [(position: Int64, handback: Data)] {
        try read { db in
            try Row.fetchAll(db, sql: "SELECT position, handback FROM watchHandback ORDER BY position").map {
                (position: $0["position"], handback: $0["handback"])
            }
        }
    }

    /// Lets go of the handbacks at `positions`, delivered now.
    public func removeWatchHandbacks(_ positions: some Collection<Int64>) throws {
        guard !positions.isEmpty else { return }
        try write { db in
            for position in positions {
                try db.execute(sql: "DELETE FROM watchHandback WHERE position = ?", arguments: [position])
            }
        }
    }

    private static func removeWatchChanges(_ ids: some Collection<String>, in db: Database) throws {
        for id in ids {
            try db.execute(sql: "DELETE FROM watchChangeDraft WHERE change = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM watchChange WHERE id = ?", arguments: [id])
        }
    }

    static func createWatchChanges(_ db: Database) throws {
        // `command` is the watch's command as JSON.
        try db.create(table: "watchChange") { table in
            table.primaryKey("id", .text)
            table.column("command", .blob).notNull()
        }
        // The replies each change queued, by draft ID, which is the `outgoing` row's.
        try db.create(table: "watchChangeDraft") { table in
            table.column("change", .text).notNull().indexed()
            table.column("draft", .text).notNull()
            table.uniqueKey(["change", "draft"])
        }
        // What the watch handed over and hasn't delivered yet, as JSON, in order.
        try db.create(table: "watchHandback") { table in
            table.autoIncrementedPrimaryKey("position")
            table.column("handback", .blob).notNull()
        }
        // The change that queued each intent (`OutboxIntent.origin`); `NULL` on every device but the watch.
        try db.alter(table: "outbox") { table in table.add(column: "origin", .text) }
        try db.create(index: "outbox_origin", on: "outbox", columns: ["origin"])
    }
}
