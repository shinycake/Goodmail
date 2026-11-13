import Foundation
import MailCore

/// A message's headers and where they came from.
struct FolderMessage: Sendable {
    var key: MessageKey
    var folderLabel: String?
    var header: IMAPMessageHeader

    init(folder: IMAPMailbox, uidValidity: UInt32, header: IMAPMessageHeader) {
        self.init(
            key: MessageKey(folder: folder.wireName, uidValidity: uidValidity, uid: header.uid),
            folderLabel: Folders.label(of: folder), header: header)
    }

    init(key: MessageKey, folderLabel: String?, header: IMAPMessageHeader) {
        self.key = key
        self.folderLabel = folderLabel
        self.header = header
    }

    var labelIDs: Set<String> { Folders.labelIDs(folderLabel: folderLabel, flags: header.flags) }
}

extension ICloudClient {
    /// Each message's thread, recording the ones the index doesn't have yet. A message keeps the thread the index has
    /// for it. Otherwise its thread is the conversation's root, the first Message-ID in its References; for a reply
    /// without References, the thread of the message it answers (or that message's ID); and for the rest, its own
    /// Message-ID, or its key when it has none.
    func threadIDs(for messages: [FolderMessage]) throws -> [MessageKey: String] {
        let known = try index.indexEntries(withKeys: messages.map(\.key.rawValue), account: accountID)
        var threadOfKey = Dictionary(known.map { ($0.key, $0.threadID) }) { first, _ in first }
        let parents = messages.compactMap { $0.header.references.isEmpty ? $0.header.inReplyTo : nil }
        var threadOfMessageID = Dictionary(
            try index.indexEntries(withInternetMessageIDs: parents, account: accountID).compactMap { entry in
                entry.internetMessageID.map { ($0, entry.threadID) }
            }
        ) { first, _ in first }
        var recorded: [MessageIndexEntry] = []
        // Oldest first, so a reply finds the thread of a message it answers in the same batch.
        for message in messages.sorted(by: { $0.header.receivedAt < $1.header.receivedAt }) {
            let key = message.key.rawValue
            let header = message.header
            let thread =
                threadOfKey[key] ?? header.references.first ?? header.inReplyTo.map { threadOfMessageID[$0] ?? $0 }
                ?? header.messageID ?? key
            if threadOfKey[key] == nil {
                recorded.append(MessageIndexEntry(key: key, threadID: thread, internetMessageID: header.messageID))
                threadOfKey[key] = thread
            }
            if let messageID = header.messageID { threadOfMessageID[messageID] = thread }
        }
        try index.record(recorded, account: accountID)
        return Dictionary(messages.map { ($0.key, threadOfKey[$0.key.rawValue] ?? $0.key.rawValue) }) { first, _ in
            first
        }
    }

    /// The summaries of these threads, from the messages already `known` and the headers of the rest of their
    /// messages, which the index names. Messages that are gone leave the index; a thread with none left is missing.
    func threads(
        _ threadIDs: Set<String>, known: [FolderMessage], in folders: Folders, on connection: IMAPConnection
    ) async throws -> ThreadFetch {
        guard !threadIDs.isEmpty else { return ThreadFetch(found: [], missing: []) }
        let entries = try index.indexEntries(inThreads: threadIDs.sorted(), account: accountID)
        let threadOfKey = Dictionary(entries.map { ($0.key, $0.threadID) }) { first, _ in first }
        let knownKeys = Set(known.map(\.key))
        let unread = entries.compactMap { MessageKey(rawValue: $0.key) }.filter { !knownKeys.contains($0) }
        var messages = known
        var gone: [MessageKey] = []
        for (folder, keys) in Dictionary(grouping: unread, by: \.folder).sorted(by: { $0.key < $1.key }) {
            guard folders.contains(folder) else {
                gone += keys
                continue
            }
            let selection = try await connection.select(folder)
            let current = keys.filter { $0.uidValidity == selection.uidValidity }
            let headers = try await connection.headers(of: current.map(\.uid))
            let found = Set(headers.map(\.uid))
            gone += keys.filter { $0.uidValidity != selection.uidValidity || !found.contains($0.uid) }
            let label = folders.label(ofFolderNamed: folder)
            messages += headers.map { header in
                FolderMessage(
                    key: MessageKey(folder: folder, uidValidity: selection.uidValidity, uid: header.uid),
                    folderLabel: label, header: header)
            }
        }
        try index.forgetIndexEntries(withKeys: gone.map(\.rawValue), account: accountID)
        let byThread = Dictionary(grouping: messages) { threadOfKey[$0.key.rawValue] ?? $0.key.rawValue }
        let found = byThread.compactMap { threadID, messages in
            threadIDs.contains(threadID) ? ThreadSummary(threadID: threadID, accountID: accountID, messages) : nil
        }
        let missing = threadIDs.subtracting(found.map(\.id.threadID))
        return ThreadFetch(found: found, missing: missing.sorted())
    }
}

extension ThreadSummary {
    /// A thread as the mailbox list shows it. A message filed in two folders, as mail to yourself is in the Inbox and
    /// in Sent, counts once and gives the thread both labels.
    fileprivate init?(threadID: String, accountID: AccountID, _ messages: [FolderMessage]) {
        let ordered = messages.sorted { $0.header.receivedAt < $1.header.receivedAt }
        guard let first = ordered.first, let latest = ordered.last else { return nil }
        let distinct = Set(ordered.map { $0.header.messageID ?? $0.key.rawValue })
        self.init(
            id: ID(accountID: accountID, threadID: threadID),
            subject: first.header.subject,
            snippet: latest.header.snippet,
            sender: latest.header.from.first ?? Contact(name: nil, address: ""),
            date: latest.header.receivedAt,
            isUnread: ordered.contains { $0.header.isUnread },
            messageCount: distinct.count,
            labelIDs: ordered.reduce(into: []) { $0.formUnion($1.labelIDs) })
    }
}
