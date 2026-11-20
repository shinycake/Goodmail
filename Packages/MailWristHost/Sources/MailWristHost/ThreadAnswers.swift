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

    /// Fetches a thread's messages with their bodies. When the store lists the thread, they're saved and returned as
    /// it keeps them, with the reader's queued changes. An alert can open a thread before the sync that lists it:
    /// those come back as fetched, without being kept.
    @concurrent private func fetchMessages(of thread: ThreadSummary.ID) async throws -> [Message] {
        let fetchedAt = Date.now
        let messages = try await provider(thread.accountID).messages(inThread: thread.threadID)
        guard !messages.isEmpty, try database.saveIfListed(messages, inThread: thread, fetchedAt: fetchedAt) else {
            return messages
        }
        return try await Self.first(database.messages(inThread: thread))
    }

    /// A thread's messages, to answer its newest: the cached ones when they reach as far as the thread does,
    /// otherwise the provider's, fetched into the store first. Offline, the cached ones are the best there is.
    @concurrent public func messagesToAnswer(in thread: ThreadSummary.ID) async throws -> [Message] {
        let newest = try database.thread(thread)?.date
        let cached = try await Self.first(database.messages(inThread: thread))
        // The store keeps the thread's date to the millisecond and each message's whole, so allow a little.
        if let newest, let last = cached.last?.date, last.timeIntervalSince(newest) > -1 { return cached }
        do {
            return try await fetchMessages(of: thread)
        } catch {
            if cached.isEmpty { throw error }
            return cached
        }
    }

    /// Sends `text` as a reply to the newest message in the thread, signed as the composer signs it, with the
    /// conversation quoted below. Returns the reply as queued; `nil`, having done nothing, for an account that is gone
    /// or a thread without messages.
    @discardableResult
    @concurrent public func reply(to thread: ThreadSummary.ID, with text: String) async throws -> Draft? {
        guard let account = try database.accounts().first(where: { $0.id == thread.accountID }) else { return nil }
        guard let latest = try await fetchMessages(of: thread).last else { return nil }
        var plain = text
        if let signature = try database.signature(for: account.id), !signature.isEmpty {
            plain += "\n\n-- \n" + signature
        }
        var draft = Draft.reply(to: latest, all: false, accountEmail: account.email, aliases: account.aliases)
        draft.body = MessageBody(html: HTMLText.lines(plain), plain: plain)
        try await commands.send(draft, after: .zero)
        return draft
    }

    /// The store's current value, without following it.
    private static func first(_ messages: AsyncThrowingStream<[Message], any Error>) async throws -> [Message] {
        for try await messages in messages { return messages }
        return []
    }
}
