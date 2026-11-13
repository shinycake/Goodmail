import Foundation
import GRDB
import MailCore

extension MailDatabase: MessageIndexStore {
    public func record(_ entries: [MessageIndexEntry], account: AccountID) throws {
        guard !entries.isEmpty else { return }
        try write { db in
            for entry in entries {
                try MessageIndexRecord(entry, accountID: account.rawValue).save(db)
            }
        }
    }

    public func indexEntries(withKeys keys: [String], account: AccountID) throws -> [MessageIndexEntry] {
        try entries(account: account, where: "key", in: keys)
    }

    public func indexEntries(inThreads threadIDs: [String], account: AccountID) throws -> [MessageIndexEntry] {
        try entries(account: account, where: "threadID", in: threadIDs)
    }

    public func indexEntries(withInternetMessageIDs ids: [String], account: AccountID) throws -> [MessageIndexEntry] {
        try entries(account: account, where: "internetMessageID", in: ids)
    }

    public func forgetIndexEntries(withKeys keys: [String], account: AccountID) throws {
        guard !keys.isEmpty else { return }
        try write { db in
            _ =
                try MessageIndexRecord
                .filter(Column("accountID") == account.rawValue && keys.contains(Column("key")))
                .deleteAll(db)
        }
    }

    private func entries(account: AccountID, where column: String, in values: [String]) throws -> [MessageIndexEntry] {
        guard !values.isEmpty else { return [] }
        return try pool.read { db in
            try MessageIndexRecord
                .filter(Column("accountID") == account.rawValue && values.contains(Column(column)))
                .order(Column("key"))
                .fetchAll(db)
                .map(\.entry)
        }
    }
}

struct MessageIndexRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "messageIndex"

    var accountID: String
    var key: String
    var threadID: String
    var internetMessageID: String?

    init(_ entry: MessageIndexEntry, accountID: String) {
        self.accountID = accountID
        key = entry.key
        threadID = entry.threadID
        internetMessageID = entry.internetMessageID
    }

    var entry: MessageIndexEntry {
        MessageIndexEntry(key: key, threadID: threadID, internetMessageID: internetMessageID)
    }
}
