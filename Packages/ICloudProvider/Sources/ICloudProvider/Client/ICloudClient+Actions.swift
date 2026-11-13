import Foundation
import MailCore

extension ICloudClient {
    /// Applies `action` to every copy of the thread's messages (`CopyPlan`): flags first, so moved copies carry them,
    /// then copies, then moves. Moved and copied messages get new UIDs, which the index learns from the server's
    /// COPYUID; a server that doesn't say leaves them to the next `changes(since:)`.
    public func perform(_ action: ThreadAction, onThread threadID: String) async throws {
        try await session.run { connection in
            let folders = Folders(try await connection.mailboxes())
            let keys = try index.indexEntries(inThreads: [threadID], account: accountID).compactMap {
                MessageKey(rawValue: $0.key)
            }
            guard !keys.isEmpty else { throw ProviderError.notFound }
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
                    let copy = try await connection.transfer(headers.map(\.uid), to: target, move: false)
                    try record(copy, of: headers, in: target, threadID: threadID)
                }
                for (target, headers) in moves.sorted(by: { $0.key < $1.key }) {
                    let copy = try await connection.transfer(headers.map(\.uid), to: target, move: true)
                    try record(copy, of: headers, in: target, threadID: threadID)
                    let moved = headers.map {
                        MessageKey(folder: folder, uidValidity: selection.uidValidity, uid: $0.uid).rawValue
                    }
                    try index.forgetIndexEntries(withKeys: moved, account: accountID)
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
