import Foundation

/// A message queued for the provider: to send once the undo window closes, or to keep in its drafts.
public struct OutgoingMessage: Identifiable, Equatable, Codable, Sendable {
    public enum Purpose: String, Codable, Sendable {
        case send
        /// Sends at a time the writer picked, which may be days away. Listed under Scheduled until it goes.
        case scheduledSend
        /// Saves the draft with the provider, replacing its earlier saved copy.
        case saveDraft
        /// Removes the draft's saved copy.
        case deleteDraft
    }

    public var id: Draft.ID { draft.id }
    public var draft: Draft
    public var purpose: Purpose
    /// When the message may go: when its undo window closes, or at its scheduled time.
    public var sendAt: Date
    /// Why the last attempt failed for good, shown to the writer. `nil` while it is still to be sent.
    public var failure: String?

    public init(draft: Draft, purpose: Purpose = .send, sendAt: Date, failure: String? = nil) {
        self.draft = draft
        self.purpose = purpose
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

    /// Sends, saves or deletes what is due. A refused message is marked failed and kept, for the writer to fix; a
    /// network failure leaves it queued for the next call. Returns the drafts the provider took.
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
            let draft: Draft
            do {
                draft = try await fetchingForwardedFiles(of: message.draft)
            } catch ProviderError.notFound {
                try? store.markFailed(message.id, reason: "A forwarded attachment is no longer available.")
                continue
            } catch {
                return sent
            }
            let raw = MIMEWriter.message(
                for: draft, from: from, date: now(),
                messageID: "\(message.id.uuidString.lowercased())@goodmail.app")
            do {
                switch message.purpose {
                case .send, .scheduledSend:
                    try await provider.send(raw, inThread: draft.threadID)
                    // A saved copy left behind is only a stale draft, not worth failing a sent message over.
                    if let saved = draft.savedDraft { try? await provider.deleteDraft(saved) }
                case .saveDraft:
                    try await provider.saveDraft(raw, inThread: draft.threadID, replacing: draft.savedDraft)
                case .deleteDraft:
                    if let saved = draft.savedDraft { try await provider.deleteDraft(saved) }
                }
                try store.remove(message.id)
                sent.append(message.draft)
            } catch ProviderError.rejected {
                try? store.markFailed(message.id, reason: "The server refused the message.")
            } catch ProviderError.notFound {
                // The thread is gone; send it on its own.
                var draft = message.draft
                draft.threadID = nil
                try? store.remove(message.id)
                try? store.enqueue(OutgoingMessage(draft: draft, purpose: message.purpose, sendAt: message.sendAt))
            } catch {
                return sent
            }
        }
        return sent
    }

    private func fetchingForwardedFiles(of draft: Draft) async throws -> Draft {
        var draft = draft
        for index in draft.attachments.indices {
            if case .forwarded(let attachment, let message) = draft.attachments[index].content {
                draft.attachments[index].content = .data(try await provider.data(for: attachment, in: message))
            }
        }
        return draft
    }
}
