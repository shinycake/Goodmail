import Foundation
import MailCore

extension IMAPClient {
    /// Compares every folder's STATUS with the cursor's, and reads what changed in the folders that differ: new UIDs,
    /// flags changed since the folder's HIGHESTMODSEQ, and with QRESYNC the UIDs expunged. Without CONDSTORE, a flag
    /// change leaves STATUS as it was, so every folder's latest messages are compared with the cursor's flags. Throws
    /// `ProviderError.cursorExpired` when a folder was added, removed or renamed, when a folder's UIDVALIDITY changed,
    /// and when messages were expunged from a server that can't say which.
    public func changes(since cursor: String) async throws -> ChangeSet {
        let old = try IMAPCursor(cursor)
        return try await session.run { connection in
            let folders = Folders(try await connection.mailboxes())
            guard Set(folders.all.map(\.wireName)) == Set(old.folders.keys) else { throw ProviderError.cursorExpired }
            var statuses: [String: IMAPFolderStatus] = [:]
            var marks: [String: [UInt32: FlagMarks]] = [:]
            var threadIDs: Set<String> = []
            for folder in folders.all {
                let status = try await connection.status(of: folder.wireName)
                statuses[folder.wireName] = status
                guard let then = old.folders[folder.wireName], status != then || status.highestModSeq == nil
                else { continue }
                let changed = try await changedThreads(
                    in: folder, from: then, to: status, marks: old.marks?[folder.wireName] ?? [:], on: connection)
                threadIDs.formUnion(changed.threadIDs)
                marks[folder.wireName] = changed.marks
            }
            return ChangeSet(threadIDs: threadIDs, cursor: IMAPCursor(folders: statuses, marks: marks).rawValue)
        }
    }

    /// The threads of `folder` that changed, and without CONDSTORE its latest messages' flags as they are now.
    private func changedThreads(
        in folder: IMAPMailbox, from then: IMAPFolderStatus, to now: IMAPFolderStatus,
        marks before: [UInt32: FlagMarks],
        on connection: IMAPConnection
    ) async throws -> (threadIDs: Set<String>, marks: [UInt32: FlagMarks]?) {
        guard now.uidValidity == then.uidValidity else { throw ProviderError.cursorExpired }
        let selection = try await connection.select(folder.wireName)
        guard selection.uidValidity == then.uidValidity else { throw ProviderError.cursorExpired }
        let added =
            now.uidNext > then.uidNext
            ? try await connection.searchUIDs(IMAPSearch(uids: then.uidNext...UInt32.max)) : []
        var flagged: [UInt32] = []
        var expunged: [UInt32]?
        var marks: [UInt32: FlagMarks]?
        if let modSeq = then.highestModSeq {
            if now.highestModSeq != modSeq { (flagged, expunged) = try await connection.changes(sinceModSeq: modSeq) }
        } else {
            let after = try await connection.flagMarks(ofLast: FlagMarks.window)
            flagged = FlagMarks.changed(from: before, to: after)
            marks = after
        }
        // Without QRESYNC, a count short of what was added means something was expunged, and nothing says what.
        if expunged == nil, now.messageCount != then.messageCount + added.count { throw ProviderError.cursorExpired }

        let headers = try await connection.headers(of: Array(Set(added + flagged)).sorted())
        let messages = headers.map { FolderMessage(folder: folder, uidValidity: then.uidValidity, header: $0) }
        var threadIDs = Set(try threadIDs(for: messages).values)
        let goneKeys = (expunged ?? []).map {
            MessageKey(folder: folder.wireName, uidValidity: then.uidValidity, uid: $0).rawValue
        }
        threadIDs.formUnion(try index.indexEntries(withKeys: goneKeys, account: accountID).map(\.threadID))
        try index.forgetIndexEntries(withKeys: goneKeys, account: accountID)
        return (threadIDs, marks)
    }

    /// The latest messages' flags of each folder on a server without CONDSTORE, for a new cursor to compare with.
    func flagMarks(
        of folders: [IMAPMailbox], statuses: [String: IMAPFolderStatus], on connection: IMAPConnection
    ) async throws -> [String: [UInt32: FlagMarks]] {
        var marks: [String: [UInt32: FlagMarks]] = [:]
        for folder in folders where statuses[folder.wireName]?.highestModSeq == nil {
            try await connection.select(folder.wireName)
            marks[folder.wireName] = try await connection.flagMarks(ofLast: FlagMarks.window)
        }
        return marks
    }
}
