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
        return OutlookCursor(
            modifiedSince: latest.value.first?.lastModifiedDateTime ?? Self.earliest, deletedItems: deletedItems
        ).rawValue
    }

    /// Throws `ProviderError.cursorExpired` for a cursor this client didn't write, and when Graph no longer keeps
    /// the Deleted Items delta it names.
    public func changes(since cursor: String) async throws -> ChangeSet {
        let old = try OutlookCursor(cursor)
        let accountID = graph.session.accountID
        var threadIDs: Set<String> = []
        var deletedItems: URL?
        // Deleted Items first: a message restored from it is reported removed there, and the query below records
        // it again where it went.
        if let link = old.deletedItems {
            let delta = try await readDelta(from: link)
            threadIDs.formUnion(delta.changed.compactMap(\.conversationId))
            let gone = delta.removed.map(\.id)
            threadIDs.formUnion(try index.indexEntries(withKeys: gone, account: accountID).map(\.threadID))
            try index.forgetIndexEntries(withKeys: gone, account: accountID)
            deletedItems = delta.next
        }
        let modified = try await messages(modifiedAfter: old.modifiedSince)
        threadIDs.formUnion(modified.compactMap(\.conversationId))
        try index.record(
            modified.compactMap { message in
                message.conversationId.map { MessageIndexEntry(key: message.id, threadID: $0) }
            }, account: accountID)
        let modifiedSince = modified.map(\.lastModifiedDateTime).max() ?? old.modifiedSince
        return ChangeSet(
            threadIDs: threadIDs,
            cursor: OutlookCursor(modifiedSince: modifiedSince, deletedItems: deletedItems).rawValue)
    }

    /// Every message modified after `date`, oldest change first.
    private func messages(modifiedAfter date: Date) async throws -> [ModifiedMessage] {
        // The literal drops fractions of a second, so the query may return the cursor's own messages again; they
        // are left out here rather than refetched on every sync.
        var next: URL? = GraphTransport.baseURL.appending(path: "me/messages").appending(queryItems: [
            URLQueryItem(name: "$filter", value: "lastModifiedDateTime ge \(Self.literal(date))"),
            URLQueryItem(name: "$orderby", value: "lastModifiedDateTime"),
            URLQueryItem(name: "$select", value: ModifiedMessage.fields),
            URLQueryItem(name: "$top", value: "1000"),
        ])
        var messages: [ModifiedMessage] = []
        while let url = next {
            let page: GraphPage<ModifiedMessage> = try await graph.get(url)
            messages += page.value.filter { $0.lastModifiedDateTime > date }
            next = page.nextLink
        }
        return messages
    }

    /// Every round of a delta query from `url`: what changed, what went, and the link for next time.
    private func readDelta(from url: URL) async throws -> (changed: [DeltaMessage], removed: [DeltaMessage], next: URL)
    {
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
            case .delta(let delta): return (changed, removed, delta)
            }
        }
    }

    private static func deltaStart(in folderID: String) -> URL {
        GraphTransport.baseURL.appending(path: "me/mailFolders/\(folderID)/messages/delta").appending(queryItems: [
            URLQueryItem(name: "$select", value: "id,conversationId")
        ])
    }
}

/// Where `changes(since:)` picks up.
struct OutlookCursor: Codable, Equatable {
    /// The newest `lastModifiedDateTime` already read, by Exchange's clock.
    var modifiedSince: Date
    /// The Deleted Items delta link, or `nil` for a mailbox without that folder.
    var deletedItems: URL?

    init(modifiedSince: Date, deletedItems: URL?) {
        self.modifiedSince = modifiedSince
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
        // A date and a URL always encode.
        return String(decoding: (try? encoder.encode(self)) ?? Data(), as: UTF8.self)
    }
}
