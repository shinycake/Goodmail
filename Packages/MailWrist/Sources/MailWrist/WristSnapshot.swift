public import Foundation
public import MailCore

/// The Inbox as the iPhone sends it to the Apple Watch (ADR-022): its newest conversations, pinned ones first, and the
/// accounts they belong to. The watch shows only this; it holds no sign-ins and reads no server.
public struct WristSnapshot: Codable, Equatable, Sendable {
    /// The wire format. A device that reads a version it doesn't know asks for the other device's app to be updated.
    public static let currentVersion = 1
    /// As many rows as the watch lists. Twenty-five rows are about 10 KB, well within what WatchConnectivity carries.
    public static let rowLimit = 25
    /// A snippet longer than this is cut, since the watch shows at most three lines of it.
    static let snippetLimit = 140

    public var version: Int
    /// When the iPhone made it.
    public var madeAt: Date
    public var accounts: [WristAccount]
    /// Pinned conversations, then the rest, each newest first.
    public var rows: [WristRow]
    /// The watch's latest commands the iPhone has run, newest last, so the watch can stop laying them over the rows.
    public var applied: [UUID]
    /// Those of `applied` that failed, so the watch can say a reply didn't go.
    public var failed: [UUID]
    /// What only the iPhone knows, for the watch to lay over the mail it reads itself (ADR-023). The watch's own
    /// snapshots carry none.
    public var extras: WristExtras?

    public init(
        version: Int = currentVersion, madeAt: Date, accounts: [WristAccount], rows: [WristRow], applied: [UUID] = [],
        failed: [UUID] = [], extras: WristExtras? = nil
    ) {
        self.version = version
        self.madeAt = madeAt
        self.accounts = accounts
        self.rows = rows
        self.applied = applied
        self.failed = failed
        self.extras = extras
    }

    /// A snapshot from before `applied`, `failed` or `extras` existed reads as having applied, or failed, nothing,
    /// and carrying no extras.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            version: try container.decode(Int.self, forKey: .version),
            madeAt: try container.decode(Date.self, forKey: .madeAt),
            accounts: try container.decode([WristAccount].self, forKey: .accounts),
            rows: try container.decode([WristRow].self, forKey: .rows),
            applied: try container.decodeIfPresent([UUID].self, forKey: .applied) ?? [],
            failed: try container.decodeIfPresent([UUID].self, forKey: .failed) ?? [],
            extras: try container.decodeIfPresent(WristExtras.self, forKey: .extras))
    }

    /// The snapshot of an Inbox: `threads` newest first, with the `pinned` ones and each account's `unread` count.
    public init(
        accounts: [Account], threads: [ThreadSummary], pinned: Set<ThreadSummary.ID>, unread: [AccountID: Int],
        applied: [UUID] = [], extras: WristExtras? = nil, madeAt: Date
    ) {
        let newestFirst = threads.sorted { $0.date > $1.date }
        let ordered = newestFirst.filter { pinned.contains($0.id) } + newestFirst.filter { !pinned.contains($0.id) }
        self.init(
            madeAt: madeAt,
            accounts: accounts.map { account in
                WristAccount(
                    id: account.id, address: account.email, color: account.color, unread: unread[account.id] ?? 0,
                    service: account.service)
            },
            rows: ordered.prefix(Self.rowLimit).map { WristRow($0, pinned: pinned.contains($0.id)) }, applied: applied,
            extras: extras)
    }

    /// Unread conversations in every account's Inbox.
    public var unread: Int { accounts.reduce(0) { $0 + $1.unread } }

    public func account(_ id: AccountID) -> WristAccount? {
        accounts.first { $0.id == id }
    }
}

public struct WristAccount: Codable, Equatable, Identifiable, Sendable {
    public var id: AccountID
    public var address: String
    public var color: AccountColor
    /// Unread conversations in its Inbox.
    public var unread: Int
    /// The service it signs in to, which says whether the watch can read it itself (ADR-023); `nil` from an iPhone
    /// that predates it.
    public var service: MailService?

    public init(id: AccountID, address: String, color: AccountColor, unread: Int, service: MailService? = nil) {
        self.id = id
        self.address = address
        self.color = color
        self.unread = unread
        self.service = service
    }
}

/// A conversation as the watch lists it.
public struct WristRow: Codable, Equatable, Identifiable, Sendable {
    public var id: ThreadSummary.ID
    /// Who wrote last.
    public var sender: Contact
    public var subject: String
    public var snippet: String
    /// The latest message's date.
    public var date: Date
    public var isUnread: Bool
    public var messageCount: Int
    public var isPinned: Bool
    /// A one-time code the subject or snippet gives, shown big so it can be read off the wrist.
    public var code: String?

    public init(
        id: ThreadSummary.ID, sender: Contact, subject: String, snippet: String, date: Date, isUnread: Bool,
        messageCount: Int, isPinned: Bool, code: String?
    ) {
        self.id = id
        self.sender = sender
        self.subject = subject
        self.snippet = snippet
        self.date = date
        self.isUnread = isUnread
        self.messageCount = messageCount
        self.isPinned = isPinned
        self.code = code
    }

    /// The snippet as words, even when the provider made it from markup: the watch never shows HTML.
    init(_ thread: ThreadSummary, pinned: Bool) {
        let snippet = SnippetText.words(of: thread.snippet)
        self.init(
            id: thread.id, sender: thread.sender, subject: thread.subject,
            snippet: String(snippet.prefix(WristSnapshot.snippetLimit)), date: thread.date,
            isUnread: thread.isUnread, messageCount: thread.messageCount, isPinned: pinned,
            code: OneTimeCode(in: thread.subject + "\n" + snippet)?.code)
    }
}
