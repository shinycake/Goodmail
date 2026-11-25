import Foundation
public import MailCore

extension IMAPClient {
    /// Compares every folder's STATUS with the cursor's, and reads what changed in the folders that differ: new UIDs,
    /// flags changed since the folder's HIGHESTMODSEQ, and with QRESYNC the UIDs expunged. Without CONDSTORE, a flag
    /// change leaves STATUS as it was, so every folder's latest messages are compared with the cursor's flags. Throws
    /// `ProviderError.cursorExpired` when a folder was added, removed or renamed, when a folder's UIDVALIDITY changed,
    /// when a folder stopped reporting a HIGHESTMODSEQ, and when messages were expunged from a server that can't say
    /// which.
    public func changes(since cursor: String) async throws -> ChangeSet {
        let old = try IMAPCursor(cursor)
        return try await session.run { connection in
            let folders = Folders(try await connection.mailboxes())
            let pairs = folders.all.compactMap { folder in old.folders[folder.wireName].map { (folder, then: $0) } }
            // Every folder is in the cursor, and every folder in the cursor is still there.
            guard pairs.count == folders.all.count, pairs.count == old.folders.count else {
                throw ProviderError.cursorExpired
            }
            var next: [String: IMAPCursor.Folder] = [:]
            var threadIDs: Set<String> = []
            for (folder, then) in pairs {
                let status = try await connection.status(of: folder.wireName)
                guard !then.isUnchanged(at: status) else {
                    next[folder.wireName] = then
                    continue
                }
                let changed = try await changedThreads(in: folder, from: then, to: status, on: connection)
                threadIDs.formUnion(changed.threadIDs)
                next[folder.wireName] = IMAPCursor.Folder(status, tracking: changed.tracking)
            }
            return ChangeSet(threadIDs: threadIDs, cursor: IMAPCursor(folders: next).rawValue)
        }
    }

    /// The threads of `folder` that changed, and how the next sync tracks its flags from here.
    private func changedThreads(
        in folder: IMAPMailbox, from then: IMAPCursor.Folder, to now: IMAPFolderStatus, on connection: IMAPConnection
    ) async throws -> (threadIDs: Set<String>, tracking: IMAPCursor.ChangeTracking) {
        guard now.uidValidity == then.uidValidity else { throw ProviderError.cursorExpired }
        let selection = try await connection.select(folder.wireName)
        guard selection.uidValidity == then.uidValidity else { throw ProviderError.cursorExpired }
        let added =
            now.uidNext > then.uidNext
            ? try await connection.searchUIDs(IMAPSearch(uids: then.uidNext...UInt32.max)) : []
        let (flagged, expunged, tracking) = try await flagChanges(from: then.tracking, to: now, on: connection)
        // Without QRESYNC, a count short of what was added means something was expunged, and nothing says what.
        if expunged == .unnamed, now.messageCount != then.messageCount + added.count {
            throw ProviderError.cursorExpired
        }

        let headers = try await connection.headers(of: Array(Set(added + flagged)).sorted())
        let messages = headers.map { FolderMessage(folder: folder, uidValidity: then.uidValidity, header: $0) }
        var threadIDs = Set(try threadIDs(for: messages).values)
        if case .named(let uids) = expunged {
            let goneKeys = uids.map {
                MessageKey(folder: folder.wireName, uidValidity: then.uidValidity, uid: $0).rawValue
            }
            threadIDs.formUnion(try index.indexEntries(withKeys: goneKeys, account: accountID).map(\.threadID))
            try index.forgetIndexEntries(withKeys: goneKeys, account: accountID)
        }
        return (threadIDs, tracking)
    }

    /// The UIDs of the selected folder whose flags changed since `tracking`, what the server says of those
    /// expunged, and the tracking for the next sync. A folder that has started reporting a HIGHESTMODSEQ is compared
    /// once more, then tracked by it; one that stopped can't say what changed since its last.
    private func flagChanges(
        from tracking: IMAPCursor.ChangeTracking, to now: IMAPFolderStatus, on connection: IMAPConnection
    ) async throws -> (flagged: [UInt32], expunged: IMAPExpunges, tracking: IMAPCursor.ChangeTracking) {
        switch (tracking, now.highestModSeq) {
        case (.modSeq(let then), let modSeq?) where modSeq == then:
            // Nothing is asked, so nothing names an expunge: the message count is what tells.
            return ([], .unnamed, .modSeq(modSeq))
        case (.modSeq(let then), let modSeq?):
            let changes = try await connection.changes(sinceModSeq: then)
            return (changes.flagged, changes.expunged, .modSeq(modSeq))
        case (.modSeq, nil):
            throw ProviderError.cursorExpired
        case (.flagMarks(let before), let modSeq):
            let after = try await connection.flagMarks(ofLast: FlagMarks.window)
            let next = modSeq.map(IMAPCursor.ChangeTracking.modSeq) ?? .flagMarks(after)
            return (FlagMarks.changed(from: before, to: after), .unnamed, next)
        }
    }

    /// Where each folder stands at `status`, for a new cursor. A folder without a HIGHESTMODSEQ is selected for its
    /// latest messages' flags, to compare.
    func cursorFolders(
        _ statuses: [(folder: IMAPMailbox, status: IMAPFolderStatus)], on connection: IMAPConnection
    ) async throws -> [String: IMAPCursor.Folder] {
        var cursor: [String: IMAPCursor.Folder] = [:]
        for (folder, status) in statuses {
            if let modSeq = status.highestModSeq {
                cursor[folder.wireName] = IMAPCursor.Folder(status, tracking: .modSeq(modSeq))
            } else {
                try await connection.select(folder.wireName)
                let marks = try await connection.flagMarks(ofLast: FlagMarks.window)
                cursor[folder.wireName] = IMAPCursor.Folder(status, tracking: .flagMarks(marks))
            }
        }
        return cursor
    }
}
