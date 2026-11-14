import MailCore

/// Builds the entities from what the host stores. Each call reads the accounts and their mailboxes once, so the
/// entities it nests share them.
struct Catalog {
    let host: any MailIntentsHost
    /// How many threads a picker or a widget suggests.
    static let suggestionLimit = 20

    func accounts() throws -> [AccountEntity] {
        try host.accounts().map(AccountEntity.init)
    }

    func mailboxes() throws -> [MailboxEntity] {
        try accounts().flatMap { account in
            try host.mailboxes(of: account.accountID).map { MailboxEntity($0, account: account) }
        }
    }

    /// With `withMessages: false` the threads carry no messages, which spares decoding every cached body when only
    /// the thread itself is wanted, as Spotlight does.
    func threads(_ identifiers: [String], withMessages: Bool = true) throws -> [ThreadEntity] {
        let threads = try host.threads(identifiers.compactMap(EntityID.thread))
        return withMessages ? try entities(for: threads) : threads.map { ThreadEntity($0, messages: []) }
    }

    func threads(matching text: String) throws -> [ThreadEntity] {
        try entities(for: host.threads(matching: text, limit: Self.suggestionLimit))
    }

    /// The newest threads in the Inbox.
    func recentThreads() throws -> [ThreadEntity] {
        try entities(for: host.threads(in: .inbox, limit: Self.suggestionLimit))
    }

    func messages(_ identifiers: [String]) throws -> [MessageEntity] {
        let ids = identifiers.compactMap(EntityID.message)
        let wanted = Set(ids.map(\.message))
        let mailboxes = try Mailboxes(catalog: self)
        return try Set(ids.map(\.thread)).flatMap { thread in
            try host.cachedMessages(inThread: thread).filter { wanted.contains($0.id) }.compactMap(
                mailboxes.entity(for:))
        }
    }

    private func entities(for threads: [ThreadSummary]) throws -> [ThreadEntity] {
        let mailboxes = try Mailboxes(catalog: self)
        return try threads.map { thread in
            ThreadEntity(
                thread, messages: try host.cachedMessages(inThread: thread.id).compactMap(mailboxes.entity(for:)))
        }
    }

    /// Every account's mailboxes, to give each message the one it's in.
    private struct Mailboxes {
        private let byID: [String: MailboxEntity]

        init(catalog: Catalog) throws {
            byID = Dictionary(try catalog.mailboxes().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        }

        /// The message's entity, or `nil` when its account is gone.
        func entity(for message: Message) -> MessageEntity? {
            let account = message.id.accountID
            let mailbox = Mailbox.holding(message.labelIDs)
            guard let entity = byID[EntityID.string(mailbox, account: account)] else { return nil }
            return MessageEntity(message, mailbox: entity, account: entity.account)
        }
    }
}

extension Mailbox {
    /// The one standard mailbox a message carrying `labels` is in: Trash and Spam hold it alone, then Drafts, the
    /// Inbox and Sent, or else All Mail.
    static func holding(_ labels: Set<String>) -> Mailbox {
        let order = [SystemLabel.trash, SystemLabel.spam, SystemLabel.draft, SystemLabel.inbox, SystemLabel.sent]
        return order.first(where: labels.contains).map { Mailbox(labelID: $0) } ?? .allMail
    }
}
