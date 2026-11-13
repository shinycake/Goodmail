import Foundation
import MailCore

#if canImport(FoundationNetworking)
    import FoundationNetworking  // URLSession on Linux
#endif

/// Microsoft Graph mail for one Outlook account. Outlook files each message in one folder and keeps Unread and
/// Starred as flags; this client reads them as Gmail's labels, and a thread is a Graph conversation.
public struct OutlookClient: MailProvider {
    let graph: GraphTransport
    /// Which conversation each message is in, so a message Graph reports deleted names the thread to refetch.
    let index: any MessageIndexStore
    private let folders = FolderCache()
    private let pageSize: Int

    /// `retryDelays` are the waits before each retry of a throttled or failed request.
    public init(
        session: OAuthSession,
        index: any MessageIndexStore,
        http: any HTTPClient = URLSession.shared,
        retryDelays: [Duration] = [.seconds(1), .seconds(2), .seconds(4)],
        pageSize: Int = 50
    ) {
        graph = GraphTransport(session: session, http: http, retryDelays: retryDelays)
        self.index = index
        self.pageSize = pageSize
    }

    public func labels() async throws -> [MailLabel] {
        let directory = try await graph.folderDirectory()
        await folders.store(directory)
        return directory.labels
    }

    public func threads(matching query: ThreadQuery, pageToken: String?) async throws -> ThreadPage {
        let url: URL
        if let pageToken, let next = URL(string: pageToken) {
            url = next
        } else if let first = try await firstPage(matching: query) {
            url = first
        } else {
            return ThreadPage(threads: [], nextPageToken: nil)
        }
        let page: GraphPage<GraphMessage> = try await graph.get(url)
        // Newest first, one entry per conversation however many of its messages the page holds.
        var seen: Set<String> = []
        let ids = page.value.compactMap(\.conversationId).filter { seen.insert($0).inserted }
        let fetch = try await threads(withIDs: ids)
        return ThreadPage(threads: fetch.found, nextPageToken: page.nextLink?.absoluteString)
    }

    public func threads(withIDs ids: [String]) async throws -> ThreadFetch {
        let directory = try await folderDirectory()
        let accountID = graph.session.accountID
        var summaries: [String: ThreadSummary] = [:]
        var entries: [MessageIndexEntry] = []
        try await withThrowingTaskGroup(of: (String, [GraphMessage]).self) { group in
            for id in ids {
                group.addTask { (id, try await conversation(id, select: GraphMessage.summaryFields)) }
            }
            for try await (id, messages) in group {
                let threadID = ThreadSummary.ID(accountID: accountID, threadID: id)
                summaries[id] = ThreadSummary(conversation: threadID, messages: messages, folders: directory)
                entries += messages.map { MessageIndexEntry(key: $0.id, threadID: id) }
            }
        }
        try index.record(entries, account: accountID)
        return ThreadFetch(found: ids.compactMap { summaries[$0] }, missing: ids.filter { summaries[$0] == nil })
    }

    /// Applies `action` to every message in the conversation, sending only the changes each message still needs.
    /// Throws `ProviderError.notFound` when the conversation is gone, and `ProviderError.rejected` for an action
    /// Outlook can't express, such as filing into a folder that no longer exists.
    public func perform(_ action: ThreadAction, onThread threadID: String) async throws {
        let messages: [GraphMessage] = try await conversation(threadID, select: GraphMessage.stateFields)
        guard !messages.isEmpty else { throw ProviderError.notFound }
        let plan: [MessagePlan]
        do {
            plan = try await self.plan(action, for: messages)
        } catch is GraphChange.Failure {
            throw ProviderError.rejected
        }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for message in plan where !message.changes.isEmpty {
                group.addTask {
                    for change in message.changes { try await graph.apply(change, toMessage: message.messageID) }
                }
            }
            try await group.waitForAll()
        }
    }

    /// Each message's changes. A folder the action names may be newer than the directory this client loaded, so a
    /// missing one is looked up once more before the action is refused.
    private func plan(
        _ action: ThreadAction, for messages: [GraphMessage]
    ) async throws -> [MessagePlan] {
        func plan(in directory: FolderDirectory) throws -> [MessagePlan] {
            try messages.map {
                MessagePlan(messageID: $0.id, changes: try GraphChange.changes(for: action, to: $0, in: directory))
            }
        }
        do {
            return try plan(in: try await folderDirectory())
        } catch GraphChange.Failure.noFolder {
            let directory = try await graph.folderDirectory()
            await folders.store(directory)
            return try plan(in: directory)
        }
    }

    /// Every message in a conversation, in whatever folder. A conversation with none left is gone.
    func conversation<Item: Decodable>(_ id: String, select: String) async throws -> [Item] {
        var messages: [Item] = []
        var next: URL? = GraphTransport.baseURL.appending(path: "me/messages").appending(queryItems: [
            URLQueryItem(name: "$filter", value: "conversationId eq \(Self.literal(id))"),
            URLQueryItem(name: "$select", value: select),
            URLQueryItem(name: "$top", value: "100"),
        ])
        while let url = next {
            let page: GraphPage<Item> = try await graph.get(url)
            messages += page.value
            next = page.nextLink
        }
        return messages
    }

    /// The first page of message IDs for `query`, or `nil` when no Outlook folder or flag matches its label, as for
    /// Gmail's categories.
    private func firstPage(matching query: ThreadQuery) async throws -> URL? {
        let directory = try await folderDirectory()
        var path = "me/messages"
        var flagFilter: String?
        switch query.label {
        case nil: break
        case SystemLabel.starred?: flagFilter = "flag/flagStatus eq 'flagged'"
        case SystemLabel.unread?: flagFilter = "isRead eq false"
        case let label?:
            guard let folder = directory.folderID(forLabel: label) else { return nil }
            path = "me/mailFolders/\(folder)/messages"
        }
        var items = [
            URLQueryItem(name: "$select", value: "id,conversationId"),
            URLQueryItem(name: "$top", value: "\(pageSize)"),
        ]
        if let text = query.text {
            // Graph ranks searches itself and takes no filter or order alongside one.
            items.append(URLQueryItem(name: "$search", value: "\"\(text.replacing("\"", with: ""))\""))
        } else {
            // Graph sorts only by a property the filter names first.
            var clauses = ["receivedDateTime ge \(Self.literal(query.since ?? Self.earliest))"]
            if let before = query.before { clauses.append("receivedDateTime lt \(Self.literal(before))") }
            if let flagFilter { clauses.append(flagFilter) }
            items.append(URLQueryItem(name: "$filter", value: clauses.joined(separator: " and ")))
            items.append(URLQueryItem(name: "$orderby", value: "receivedDateTime desc"))
        }
        return GraphTransport.baseURL.appending(path: path).appending(queryItems: items)
    }

    func folderDirectory() async throws -> FolderDirectory {
        try await folders.directory { [graph] in try await graph.folderDirectory() }
    }

    /// Before any mail, so a filter on the date can lead without leaving anything out.
    static let earliest = Date(timeIntervalSince1970: 0)

    /// An OData string literal, its quotes doubled.
    static func literal(_ text: String) -> String {
        "'\(text.replacing("'", with: "''"))'"
    }

    /// An OData date literal, in UTC.
    static func literal(_ date: Date) -> String {
        date.formatted(.iso8601)
    }
}
