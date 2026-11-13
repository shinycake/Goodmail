import Foundation
import MailCore

#if canImport(FoundationNetworking)
    import FoundationNetworking  // URLSession on Linux
#endif

/// Incremental sync. Every message Exchange changes, by a move, a flag or arriving, gets a new
/// `lastModifiedDateTime`, so the conversations of the messages modified since the cursor are the ones to refetch.
/// A message deleted for good leaves nothing to find that way, and mail is deleted for good almost always from
/// Deleted Items, so that folder's delta query reports those and the message index names their conversations.
extension OutlookClient {
    public func currentCursor() async throws -> String {
        let latest: GraphPage<ModifiedMessage> = try await graph.get(
            "me/messages",
            query: [
                URLQueryItem(name: "$select", value: ModifiedMessage.fields),
                URLQueryItem(name: "$orderby", value: "lastModifiedDateTime desc"),
                URLQueryItem(name: "$top", value: "1"),
            ])
        var deletedItems: URL?
        if let folder = try await folderDirectory().wellKnown[.deleteditems] {
            deletedItems = try await readDelta(from: Self.deltaStart(in: folder)).next
        }
        let newest = latest.value.first
        return OutlookCursor(
            modifiedSince: newest?.lastModifiedDateTime ?? Self.earliest,
            readAtModifiedSince: Set(newest.map { [$0.id] } ?? []), deletedItems: deletedItems
        ).rawValue
    }

    /// Throws `ProviderError.cursorExpired` for a cursor this client didn't write, and when Graph no longer keeps
    /// the Deleted Items delta it names.
    ///
    /// Everything is read before the index changes, so a sync that fails partway leaves the index as it was and its
    /// retry, from the same cursor, finds the same deleted messages' conversations.
    public func changes(since cursor: String) async throws -> ChangeSet {
        let old = try OutlookCursor(cursor)
        let accountID = graph.session.accountID
        let delta: DeltaRound? = if let link = old.deletedItems { try await readDelta(from: link) } else { nil }
        let modified = try await messages(changedSince: old)

        let gone = delta?.removed.map(\.id) ?? []
        var threadIDs = Set(try index.indexEntries(withKeys: gone, account: accountID).map(\.threadID))
        threadIDs.formUnion((delta?.changed ?? []).compactMap(\.conversationId))
        threadIDs.formUnion(modified.compactMap(\.conversationId))
        // Forget before recording: a message restored from Deleted Items is reported removed there and modified
        // where it went, and stays in the index.
        try index.forgetIndexEntries(withKeys: gone, account: accountID)
        try index.record(
            modified.compactMap { message in
                message.conversationId.map { MessageIndexEntry(key: message.id, threadID: $0) }
            }, account: accountID)
        return ChangeSet(
            threadIDs: threadIDs, cursor: old.advanced(past: modified, deletedItems: delta?.next).rawValue)
    }

    /// Every message changed since `cursor`, oldest change first. Several messages can share a timestamp, so one
    /// changed at the cursor's own time is new unless the cursor already read it.
    private func messages(changedSince cursor: OutlookCursor) async throws -> [ModifiedMessage] {
        // The literal drops fractions of a second, so the query also returns messages from just before the cursor;
        // they are left out here.
        var next: URL? = GraphTransport.baseURL.appending(path: "me/messages").appending(queryItems: [
            URLQueryItem(name: "$filter", value: "lastModifiedDateTime ge \(Self.literal(cursor.modifiedSince))"),
            URLQueryItem(name: "$orderby", value: "lastModifiedDateTime"),
            URLQueryItem(name: "$select", value: ModifiedMessage.fields),
            URLQueryItem(name: "$top", value: "1000"),
        ])
        var messages: [ModifiedMessage] = []
        while let url = next {
            let page: GraphPage<ModifiedMessage> = try await graph.get(url)
            messages += page.value.filter(cursor.isNew)
            next = page.nextLink
        }
        return messages
    }

    /// Every round of a delta query from `url`: what changed, what went, and the link for next time.
    private func readDelta(from url: URL) async throws -> DeltaRound {
        var changed: [DeltaMessage] = []
        var removed: [DeltaMessage] = []
        var url = url
        while true {
            let page: GraphDeltaPage<DeltaMessage>
            do {
                page = try await graph.get(url)
            } catch let error as GraphError where error.status == 410 {
                // Graph forgot this delta's state; only a full sync catches up.
                throw ProviderError.cursorExpired
            }
            for message in page.value {
                if message.removed == nil { changed.append(message) } else { removed.append(message) }
            }
            switch page.link {
            case .next(let next): url = next
            case .delta(let delta): return DeltaRound(changed: changed, removed: removed, next: delta)
            }
        }
    }

    private static func deltaStart(in folderID: String) -> URL {
        GraphTransport.baseURL.appending(path: "me/mailFolders/\(folderID)/messages/delta").appending(queryItems: [
            URLQueryItem(name: "$select", value: "id,conversationId")
        ])
    }
}

/// One delta query read to its end: what changed, what went, and the link for next time.
struct DeltaRound {
    let changed: [DeltaMessage]
    let removed: [DeltaMessage]
    let next: URL
}

/// Where `changes(since:)` picks up.
struct OutlookCursor: Codable, Equatable {
    /// The newest `lastModifiedDateTime` already read, by Exchange's clock.
    var modifiedSince: Date
    /// The messages already read whose change is at `modifiedSince`, so another change at that same time still
    /// counts.
    var readAtModifiedSince: Set<String>
    /// The Deleted Items delta link, or `nil` for a mailbox without that folder.
    var deletedItems: URL?

    init(modifiedSince: Date, readAtModifiedSince: Set<String>, deletedItems: URL?) {
        self.modifiedSince = modifiedSince
        self.readAtModifiedSince = readAtModifiedSince
        self.deletedItems = deletedItems
    }

    /// Throws `ProviderError.cursorExpired` for a cursor this client didn't write.
    init(_ rawValue: String) throws {
        guard let cursor = try? JSONDecoder().decode(Self.self, from: Data(rawValue.utf8)) else {
            throw ProviderError.cursorExpired
        }
        self = cursor
    }

    var rawValue: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        do {
            return String(decoding: try encoder.encode(self), as: UTF8.self)
        } catch {
            preconditionFailure("A date, message IDs and a URL always encode as JSON: \(error)")
        }
    }

    /// Whether `message` changed after this cursor.
    func isNew(_ message: ModifiedMessage) -> Bool {
        message.lastModifiedDateTime > modifiedSince
            || (message.lastModifiedDateTime == modifiedSince && !readAtModifiedSince.contains(message.id))
    }

    /// The cursor once `modified` has been read.
    func advanced(past modified: [ModifiedMessage], deletedItems: URL?) -> OutlookCursor {
        guard let newest = modified.map(\.lastModifiedDateTime).max() else {
            return OutlookCursor(
                modifiedSince: modifiedSince, readAtModifiedSince: readAtModifiedSince, deletedItems: deletedItems)
        }
        let atNewest = Set(modified.filter { $0.lastModifiedDateTime == newest }.map(\.id))
        return OutlookCursor(
            modifiedSince: newest,
            readAtModifiedSince: newest == modifiedSince ? readAtModifiedSince.union(atNewest) : atNewest,
            deletedItems: deletedItems)
    }
}
