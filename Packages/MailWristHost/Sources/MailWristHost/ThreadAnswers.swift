import Foundation
public import MailCore
public import MailStore

/// Answers a conversation from wherever the reader is: a reply from an alert, or from the watch. Reads the messages
/// it needs from the store, fetching them first when the store's copy is behind.
public struct ThreadAnswers: Sendable {
    private let database: MailDatabase
    private let commands: MailCommands
    private let provider: @Sendable (AccountID) throws -> any MailProvider

    public init(
        database: MailDatabase, commands: MailCommands,
        provider: @escaping @Sendable (AccountID) throws -> any MailProvider
    ) {
        self.database = database
        self.commands = commands
        self.provider = provider
    }

    /// Fetches a thread's messages with their bodies into the store.
    @concurrent public func loadMessages(of thread: ThreadSummary.ID) async throws {
        let fetchedAt = Date.now
        let messages = try await provider(thread.accountID).messages(inThread: thread.threadID)
        try database.save(messages, inThread: thread, fetchedAt: fetchedAt)
    }

    /// A thread's messages, to answer its newest: the cached ones when they reach as far as the thread does,
    /// otherwise the provider's, fetched into the store first. Offline, the cached ones are the best there is.
    @concurrent public func messagesToAnswer(in thread: ThreadSummary.ID) async throws -> [Message] {
        let newest = try database.thread(thread)?.date
        let cached = try await Self.first(database.messages(inThread: thread))
        // The store keeps the thread's date to the millisecond and each message's whole, so allow a little.
        if let newest, let last = cached.last?.date, last.timeIntervalSince(newest) > -1 { return cached }
        do {
            try await loadMessages(of: thread)
        } catch {
            if cached.isEmpty { throw error }
            return cached
        }
        return try await Self.first(database.messages(inThread: thread))
    }

    /// Sends `text` as a reply to the newest message in the thread, signed as the composer signs it, with the
    /// conversation quoted below. Does nothing for an account that is gone or a thread without messages.
    @concurrent public func reply(to thread: ThreadSummary.ID, with text: String) async throws {
        guard let account = try database.accounts().first(where: { $0.id == thread.accountID }) else { return }
        let fetchedAt = Date.now
        let messages = try await provider(thread.accountID).messages(inThread: thread.threadID)
        guard let latest = messages.last else { return }
        try database.save(messages, inThread: thread, fetchedAt: fetchedAt)
        var plain = text
        if let signature = try database.signature(for: account.id), !signature.isEmpty {
            plain += "\n\n-- \n" + signature
        }
        var draft = Draft.reply(to: latest, all: false, accountEmail: account.email, aliases: account.aliases)
        draft.body = MessageBody(html: HTMLText.lines(plain), plain: plain)
        try await commands.send(draft, after: .zero)
    }

    /// The store's current value, without following it.
    private static func first(_ messages: AsyncThrowingStream<[Message], any Error>) async throws -> [Message] {
        for try await messages in messages { return messages }
        return []
    }
}
