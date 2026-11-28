import Foundation
import MailCore

/// Builds the entities from what the host stores. Each call reads the accounts and their mailboxes once, so the
/// entities it nests share them.
struct Catalog {
    let host: any MailIntentsHost
    /// How many threads a picker or a widget suggests.
    static let suggestionLimit = 20
    /// The calendar a message's weekday and hour are read in.
    var calendar: Calendar = .current
    /// The moment ages are read from.
    var now: Date = .now

    func accounts() async throws -> [AccountEntity] {
        try await host.accounts().map(AccountEntity.init)
    }

    /// Every account's mailboxes, in the accounts' order, read side by side.
    func mailboxes() async throws -> [MailboxEntity] {
        let accounts = try await accounts()
        let host = host
        let byAccount = try await withThrowingTaskGroup(of: (Int, [MailboxEntity]).self) { group in
            for (index, account) in accounts.enumerated() {
                group.addTask {
                    (index, try await host.mailboxes(of: account.accountID).map { MailboxEntity($0, account: account) })
                }
            }
            return try await group.reduce(into: [Int: [MailboxEntity]]()) { $0[$1.0] = $1.1 }
        }
        return accounts.indices.flatMap { byAccount[$0] ?? [] }
    }

    /// With `withMessages: false` the threads carry no messages, which spares decoding every cached body when only
    /// the thread itself is wanted, as Spotlight does.
    func threads(_ identifiers: [String], withMessages: Bool = true) async throws -> [ThreadEntity] {
        try await threads(ids: identifiers.compactMap(EntityID.thread), withMessages: withMessages)
    }

    func threads(matching text: String) async throws -> [ThreadEntity] {
        try await threads(ids: host.threads(matching: text, limit: Self.suggestionLimit).map(\.id))
    }

    /// The newest threads in the Inbox.
    func recentThreads() async throws -> [ThreadEntity] {
        try await threads(ids: host.threads(in: .inbox, limit: Self.suggestionLimit).map(\.id))
    }

    /// The stored threads among `ids`, newest first.
    func threads(ids: [ThreadSummary.ID], withMessages: Bool = true) async throws -> [ThreadEntity] {
        // In the order asked for, as the identifiers were given.
        let position = Dictionary(ids.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let inOrder: ([MailFacts]) -> [MailFacts] = { facts in
            facts.sorted { position[$0.envelope.thread, default: .max] < position[$1.envelope.thread, default: .max] }
        }
        guard withMessages else {
            return inOrder(try await host.threadFacts(ids)).map { ThreadEntity($0, messages: [], now: now) }
        }
        // The threads, their cached messages and every account's mailboxes, read side by side.
        async let facts = host.threadFacts(ids)
        async let cached = host.messageFacts(inThreads: ids)
        async let made = Messages(catalog: self)
        let threads = inOrder(try await facts)
        let byThread = Dictionary(grouping: try await cached, by: \.envelope.thread)
        let messages = try await made
        return threads.map { thread in
            let conversation = [thread.envelope.thread: ThreadEntity(thread, messages: [], now: now)]
            // Oldest first, as a conversation reads.
            let cached = messages.entities(
                (byThread[thread.envelope.thread] ?? []).reversed(), conversations: conversation)
            return ThreadEntity(thread, messages: cached, now: now)
        }
    }

    func messages(_ identifiers: [String]) async throws -> [MessageEntity] {
        let ids = identifiers.compactMap(EntityID.message)
        let wanted = Set(ids.map(\.message))
        let facts = try await host.messageFacts(inThreads: Array(Set(ids.map(\.thread))))
            .filter { $0.content.map { wanted.contains($0.id) } ?? false }
        return try await entities(of: facts)
    }

    /// The cached messages that meet `condition`, in `sorts`' order, at most `limit` of them. Reads every cached body
    /// the condition's dates allow, so it runs off the caller's actor.
    @concurrent func messages(matching condition: MailCondition, sortedBy sorts: [MailSort], limit: Int?)
        async throws -> [MessageEntity]
    {
        let found = try await host.messageFacts(matching: condition, in: MailCondition.Context(calendar: calendar))
        let sorted = MailSort.sorted(found, by: sorts)
        let kept = limit.map { Array(sorted.prefix($0)) } ?? sorted
        return try await entities(of: kept)
    }

    /// The messages' entities, with every account's mailboxes and the messages' conversations read side by side.
    private func entities(of facts: [MailFacts]) async throws -> [MessageEntity] {
        async let made = Messages(catalog: self)
        async let threads = conversations(of: facts)
        return try await made.entities(facts, conversations: threads)
    }

    /// The stored threads that meet `condition`, in `sorts`' order, at most `limit` of them, without their messages.
    @concurrent func threads(matching condition: MailCondition, sortedBy sorts: [MailSort], limit: Int?)
        async throws -> [ThreadEntity]
    {
        let found = try await host.threadFacts(matching: condition, in: MailCondition.Context(calendar: calendar))
        let sorted = MailSort.sorted(found, by: sorts)
        return (limit.map { Array(sorted.prefix($0)) } ?? sorted).map { ThreadEntity($0, messages: [], now: now) }
    }

    /// The conversations the messages belong to, without their messages, by ID.
    private func conversations(of messages: [MailFacts]) async throws -> [ThreadSummary.ID: ThreadEntity] {
        let ids = Array(Set(messages.map(\.envelope.thread)))
        return Dictionary(
            try await host.threadFacts(ids).map { ($0.envelope.thread, ThreadEntity($0, messages: [], now: now)) },
            uniquingKeysWith: { first, _ in first })
    }

    /// Makes message entities, each in the mailbox it's in among every account's.
    private struct Messages {
        private let byID: [String: MailboxEntity]
        private let calendar: Calendar
        private let now: Date

        init(catalog: Catalog) async throws {
            byID = Dictionary(
                try await catalog.mailboxes().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            calendar = catalog.calendar
            now = catalog.now
        }

        /// The messages' entities, each with its conversation from `conversations`, leaving out any whose account is
        /// gone or that isn't cached. A message whose conversation isn't stored stands for it itself.
        func entities(_ facts: [MailFacts], conversations: [ThreadSummary.ID: ThreadEntity]) -> [MessageEntity] {
            facts.compactMap { facts in
                let mailbox = Mailbox.holding(facts.envelope.labelIDs)
                guard let content = facts.content,
                    let entity = byID[EntityID.string(mailbox, account: facts.envelope.account.id)]
                else { return nil }
                let conversation = conversations[facts.envelope.thread] ?? ThreadEntity(facts, messages: [], now: now)
                return MessageEntity(
                    facts, content: content, mailbox: entity, conversation: conversation, calendar: calendar, now: now)
            }
        }
    }
}
