import Foundation
import MailCore

/// A `MessageIndexStore` in memory, for one account.
final class MemoryIndex: MessageIndexStore, @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String: MessageIndexEntry] = [:]

    init(_ entries: [MessageIndexEntry] = []) {
        for entry in entries { self.entries[entry.key] = entry }
    }

    var all: [MessageIndexEntry] {
        lock.withLock { entries.values.sorted { $0.key < $1.key } }
    }

    func record(_ entries: [MessageIndexEntry], account: AccountID) throws {
        lock.withLock { for entry in entries { self.entries[entry.key] = entry } }
    }

    func indexEntries(withKeys keys: [String], account: AccountID) throws -> [MessageIndexEntry] {
        all.filter { keys.contains($0.key) }
    }

    func indexEntries(inThreads threadIDs: [String], account: AccountID) throws -> [MessageIndexEntry] {
        all.filter { threadIDs.contains($0.threadID) }
    }

    func indexEntries(withInternetMessageIDs ids: [String], account: AccountID) throws -> [MessageIndexEntry] {
        all.filter { $0.internetMessageID.map(ids.contains) ?? false }
    }

    func forgetIndexEntries(withKeys keys: [String], account: AccountID) throws {
        lock.withLock { for key in keys { entries[key] = nil } }
    }
}
