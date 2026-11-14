import Foundation
import MailCore

extension ICloudClient {
    /// Applies `action` to every copy of the thread's messages (`CopyPlan`): flags first, so moved copies carry them,
    /// then copies, then moves. Copies the action deletes, as Delete Forever does those in Trash, are expunged. Moved and copied messages get new UIDs, which the index learns from the server's
    /// COPYUID; a server that doesn't say leaves them to the next `changes(since:)`.
    ///
    /// A folder never gets a second copy of a message, so replaying an action changes nothing: a copy isn't filed
    /// where the index already has one, and a copy that would move there is removed instead.
    public func perform(_ action: ThreadAction, onThread threadID: String) async throws {
        try await session.run { connection in
            let folders = Folders(try await connection.mailboxes())
            let entries = try index.indexEntries(inThreads: [threadID], account: accountID)
            let keys = entries.compactMap { MessageKey(rawValue: $0.key) }
            guard !keys.isEmpty else { throw ProviderError.notFound }
            var filed = Set(
                entries.compactMap { entry in
                    entry.internetMessageID.flatMap { id in
                        MessageKey(rawValue: entry.key).map { Filed(id, in: $0.folder) }
                    }
                })
            for (folder, keys) in Dictionary(grouping: keys, by: \.folder).sorted(by: { $0.key < $1.key })
            where folders.contains(folder) {
                let selection = try await connection.select(folder)
                let uids = keys.filter { $0.uidValidity == selection.uidValidity }.map(\.uid)
                let headers = try await connection.headers(of: uids)
                let label = folders.label(ofFolderNamed: folder)
                let plans = headers.map {
                    (header: $0, plan: CopyPlan(action: action, folderLabel: label, flags: $0.flags))
                }
                try await store(plans.map { ($0.header.uid, $0.plan) }, on: connection)

                var moves: [String: [IMAPMessageHeader]] = [:]
                var copies: [String: [IMAPMessageHeader]] = [:]
                let expunged = plans.filter { $0.plan.placement == .expunge }.map(\.header.uid)
                try await connection.expunge(expunged)
                try index.forgetIndexEntries(
                    withKeys: expunged.map {
                        MessageKey(folder: folder, uidValidity: selection.uidValidity, uid: $0).rawValue
                    },
                    account: accountID)
                for (header, plan) in plans {
                    for copy in plan.copies {
                        if let target = folders.folder(for: copy) {
                            copies[target.wireName, default: []].append(header)
                        }
                    }
                    if case .move(let label) = plan.placement, let target = folders.folder(for: label) {
                        moves[target.wireName, default: []].append(header)
                    }
                }
                for (target, headers) in copies.sorted(by: { $0.key < $1.key }) {
                    let new = headers.filter { !filed.contains(Filed($0.messageID, in: target)) }
                    let copy = try await connection.transfer(new.map(\.uid), to: target, move: false)
                    try record(copy, of: new, in: target, threadID: threadID)
                    filed.formUnion(new.compactMap { header in header.messageID.map { Filed($0, in: target) } })
                }
                for (target, headers) in moves.sorted(by: { $0.key < $1.key }) {
                    let (redundant, new) = headers.partitioned { filed.contains(Filed($0.messageID, in: target)) }
                    try await connection.expunge(redundant.map(\.uid))
                    let copy = try await connection.transfer(new.map(\.uid), to: target, move: true)
                    try record(copy, of: new, in: target, threadID: threadID)
                    filed.formUnion(new.compactMap { header in header.messageID.map { Filed($0, in: target) } })
                    let gone = headers.map {
                        MessageKey(folder: folder, uidValidity: selection.uidValidity, uid: $0.uid).rawValue
                    }
                    try index.forgetIndexEntries(withKeys: gone, account: accountID)
                }
            }
        }
    }

    /// Stores each flag change on every UID it applies to, one command per flag and direction.
    private func store(_ plans: [(uid: UInt32, plan: CopyPlan)], on connection: IMAPConnection) async throws {
        for flag in [CopyPlan.seen, CopyPlan.flagged] {
            try await connection.store(
                [flag], add: true, on: plans.filter { $0.plan.addFlags.contains(flag) }.map(\.uid))
            try await connection.store(
                [flag], add: false, on: plans.filter { $0.plan.removeFlags.contains(flag) }.map(\.uid))
        }
    }

    /// Indexes the messages a COPY or MOVE put in `folder`, in the thread they came from.
    private func record(_ copy: IMAPCopy?, of headers: [IMAPMessageHeader], in folder: String, threadID: String) throws
    {
        guard let copy else { return }
        let entries = headers.compactMap { header in
            copy.uids[header.uid].map { uid in
                MessageIndexEntry(
                    key: MessageKey(folder: folder, uidValidity: copy.uidValidity, uid: uid).rawValue,
                    threadID: threadID, internetMessageID: header.messageID)
            }
        }
        try index.record(entries, account: accountID)
    }
}

/// A message, by its Message-ID, filed in a folder.
private struct Filed: Hashable {
    var messageID: String
    var folder: String

    init(_ messageID: String, in folder: String) {
        self.messageID = messageID
        self.folder = folder
    }

    /// A message without a Message-ID can't be matched with its copies, so it never counts as filed.
    init(_ messageID: String?, in folder: String) {
        self.init(messageID ?? "", in: folder)
    }
}

extension Array {
    /// The elements that match, and the rest, each in order.
    fileprivate func partitioned(by matches: (Element) -> Bool) -> (matching: [Element], rest: [Element]) {
        (filter(matches), filter { !matches($0) })
    }
}
