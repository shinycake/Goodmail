import GRDB
public import MailCore

/// What the database holds of the accounts that screens read at once: the accounts in the reader's order and their
/// signatures. The app follows it (`MailFollowing.accountsAndSignatures()`), so it never reads the database on the
/// main actor for them, and every writer, a sync, Settings or another process, reaches it (ADR-043).
public struct StoredAccounts: Equatable, Revised {
    public let accounts: [Account]
    /// Each account's signature, where one is set.
    public let signatures: [AccountID: String]
    /// Counts the writes that changed what this holds, in whichever process: the database bumps it in the same
    /// transaction as each one. A write's own revision (as `MailDatabase.save(_:)` returns it) is shown once a
    /// followed value is at least that new, whatever other writes changed since.
    public let revision: Int

    public init(accounts: [Account], signatures: [AccountID: String], revision: Int) {
        self.accounts = accounts
        self.signatures = signatures
        self.revision = revision
    }

    init(_ db: Database) throws {
        accounts = try MailDatabase.accounts(db)
        signatures = try MailDatabase.signatures(db)
        revision = try MailDatabase.accountsRevision(db)
    }
}

extension MailDatabase {
    /// The accounts and their signatures as stored now.
    public func storedAccounts() throws -> StoredAccounts {
        try read { try StoredAccounts($0) }
    }

    /// The accounts' revision now: a followed value at least this new shows every write to them made before.
    public func accountsRevision() throws -> Int {
        try read(Self.accountsRevision)
    }

    static func accountsRevision(_ db: Database) throws -> Int {
        try Int.fetchOne(db, sql: "SELECT revision FROM accountsRevision") ?? 0
    }

    /// Keeps the accounts' revision: one row, bumped by triggers in the same transaction as any write that changes
    /// what `StoredAccounts` reads, so every writer bumps it, this app, a sync or the notification extension, and a
    /// write that changes nothing, as a sync storing the same aliases again, doesn't. The update trigger watches every
    /// column of `account` but those `StoredAccountsTests.columnsTheRevisionLeavesOut` lists: a new column needs a
    /// migration that makes the trigger again with it.
    static func reviseAccounts(_ db: Database) throws {
        try db.execute(
            sql: """
                CREATE TABLE accountsRevision (id INTEGER PRIMARY KEY CHECK (id = 0), revision INTEGER NOT NULL);
                INSERT INTO accountsRevision (id, revision) VALUES (0, 0);
                CREATE TRIGGER account_revisedByInsert AFTER INSERT ON account BEGIN
                    UPDATE accountsRevision SET revision = revision + 1;
                END;
                CREATE TRIGGER account_revisedByDelete AFTER DELETE ON account BEGIN
                    UPDATE accountsRevision SET revision = revision + 1;
                END;
                CREATE TRIGGER account_revisedByUpdate AFTER UPDATE ON account
                WHEN OLD.id IS NOT NEW.id OR OLD.email IS NOT NEW.email OR OLD.color IS NOT NEW.color
                    OR OLD.service IS NOT NEW.service OR OLD.name IS NOT NEW.name OR OLD.nickname IS NOT NEW.nickname
                    OR OLD.aliases IS NOT NEW.aliases OR OLD.signature IS NOT NEW.signature
                    OR OLD.position IS NOT NEW.position OR OLD.createdAt IS NOT NEW.createdAt
                BEGIN
                    UPDATE accountsRevision SET revision = revision + 1;
                END;
                """)
    }
}

extension MailFollowing {
    /// Follows the accounts and their signatures: now, then after each change to either, in the order they were
    /// written.
    public func accountsAndSignatures() -> AsyncThrowingStream<StoredAccounts, any Error> {
        followed.observe { try StoredAccounts($0) }
    }
}
