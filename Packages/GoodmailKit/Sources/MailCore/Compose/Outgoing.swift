import Foundation

/// A message queued to send. It waits out the undo window, then goes to the provider.
public struct OutgoingMessage: Identifiable, Equatable, Codable, Sendable {
    public var id: Draft.ID { draft.id }
    public var draft: Draft
    /// When the undo window closes and the message may go.
    public var sendAt: Date
    /// Why the last attempt failed for good, shown to the writer. `nil` while it is still to be sent.
    public var failure: String?

    public init(draft: Draft, sendAt: Date, failure: String? = nil) {
        self.draft = draft
        self.sendAt = sendAt
        self.failure = failure
    }
}

/// The persistence the send queue needs. `MailStore` implements it.
public protocol OutgoingStore: Sendable {
    func enqueue(_ message: OutgoingMessage) throws
    /// Removes a message that hasn't gone yet. Returns it, or `nil` when it already went.
    func cancel(_ id: Draft.ID) throws -> OutgoingMessage?
    /// Messages due by `date` that haven't failed, oldest first.
    func dueMessages(for account: AccountID, by date: Date) throws -> [OutgoingMessage]
    /// The earliest time a waiting message falls due.
    func nextSendDate(for account: AccountID) throws -> Date?
    func markFailed(_ id: Draft.ID, reason: String) throws
    func remove(_ id: Draft.ID) throws
}

/// Sends one account's due messages, oldest first.
public actor Sender {
    public nonisolated let accountID: AccountID
    private let provider: any MailProvider
    private let store: any OutgoingStore
    private let from: Contact
    private let now: @Sendable () -> Date
    private var running: Task<[Draft], Never>?

    public init(
        accountID: AccountID,
        provider: any MailProvider,
        store: any OutgoingStore,
        from: Contact,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.accountID = accountID
        self.provider = provider
        self.store = store
        self.from = from
        self.now = now
    }

    /// Sends what is due. A refused message is marked failed and kept, for the writer to fix; a network failure
    /// leaves it queued for the next call. Returns the drafts that were sent.
    @discardableResult
    public func flush() async -> [Draft] {
        if let running { return await running.value }
        let task = Task { await drain() }
        running = task
        defer { running = nil }
        return await task.value
    }

    private func drain() async -> [Draft] {
        var sent: [Draft] = []
        while let message = (try? store.dueMessages(for: accountID, by: now()))?.first {
            let raw = MIMEWriter.message(
                for: message.draft, from: from, date: now(),
                messageID: "\(message.id.uuidString.lowercased())@goodmail.app")
            do {
                try await provider.send(raw, inThread: message.draft.threadID)
                try store.remove(message.id)
                sent.append(message.draft)
            } catch ProviderError.rejected {
                try? store.markFailed(message.id, reason: "The server refused the message.")
            } catch ProviderError.notFound {
                // The thread is gone; send it on its own.
                var draft = message.draft
                draft.threadID = nil
                try? store.remove(message.id)
                try? store.enqueue(OutgoingMessage(draft: draft, sendAt: message.sendAt))
            } catch {
                return sent
            }
        }
        return sent
    }
}
