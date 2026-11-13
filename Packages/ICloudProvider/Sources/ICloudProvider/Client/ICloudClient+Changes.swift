import Foundation
import MailCore

extension ICloudClient {
    /// Compares every folder's STATUS with the cursor's, and reads what changed in the folders that differ: new UIDs,
    /// flags changed since the folder's HIGHESTMODSEQ, and with QRESYNC the UIDs expunged. Throws
    /// `ProviderError.cursorExpired` when a folder was added, removed or renamed, when a folder's UIDVALIDITY changed,
    /// and when messages were expunged from a server that can't say which.
    public func changes(since cursor: String) async throws -> ChangeSet {
        let old = try ICloudCursor(cursor)
        return try await session.run { connection in
            let folders = Folders(try await connection.mailboxes())
            guard Set(folders.all.map(\.wireName)) == Set(old.folders.keys) else { throw ProviderError.cursorExpired }
            var statuses: [String: IMAPFolderStatus] = [:]
            var threadIDs: Set<String> = []
            for folder in folders.all {
                let status = try await connection.status(of: folder.wireName)
                statuses[folder.wireName] = status
                guard let then = old.folders[folder.wireName], status != then else { continue }
                threadIDs.formUnion(try await changedThreads(in: folder, from: then, to: status, on: connection))
            }
            return ChangeSet(threadIDs: threadIDs, cursor: ICloudCursor(folders: statuses).rawValue)
        }
    }

    private func changedThreads(
        in folder: IMAPMailbox, from then: IMAPFolderStatus, to now: IMAPFolderStatus, on connection: IMAPConnection
    ) async throws -> Set<String> {
        guard now.uidValidity == then.uidValidity else { throw ProviderError.cursorExpired }
        let selection = try await connection.select(folder.wireName)
        guard selection.uidValidity == then.uidValidity else { throw ProviderError.cursorExpired }
        let added =
            now.uidNext > then.uidNext
            ? try await connection.searchUIDs(IMAPSearch(uids: then.uidNext...UInt32.max)) : []
        var flagged: [UInt32] = []
        var expunged: [UInt32]?
        if let modSeq = then.highestModSeq, now.highestModSeq != modSeq {
            (flagged, expunged) = try await connection.changes(sinceModSeq: modSeq)
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
        return threadIDs
    }
}
