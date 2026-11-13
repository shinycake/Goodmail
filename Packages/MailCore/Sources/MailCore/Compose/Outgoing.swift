import Foundation

/// A message queued for the provider: to send once the undo window closes, or to keep in its drafts.
public struct OutgoingMessage: Identifiable, Equatable, Codable, Sendable {
    public enum Purpose: String, Codable, Sendable {
        case send
        /// Saves the draft with the provider, replacing its earlier saved copy.
        case saveDraft
        /// Removes the draft's saved copy.
        case deleteDraft
    }

    public var id: Draft.ID { draft.id }
    public var draft: Draft
    public var purpose: Purpose
    /// When the undo window closes and the message may go.
    public var sendAt: Date
    /// Why the last attempt failed for good. `nil` while it is still to be sent.
    public var failure: SendFailure?

    public init(draft: Draft, purpose: Purpose = .send, sendAt: Date, failure: SendFailure? = nil) {
        self.draft = draft
        self.purpose = purpose
        self.sendAt = sendAt
        self.failure = failure
    }
}

/// Why a queued message failed for good. Stored as its raw value and worded by the UI in the reader's language.
public enum SendFailure: String, Codable, Sendable {
    /// A file forwarded from another message is gone from the server.
    case forwardedAttachmentMissing
    /// The server refused the message.
    case rejected
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
    func markFailed(_ id: Draft.ID, reason: SendFailure) throws
    func remove(_ id: Draft.ID) throws
    /// Who the account's mail is from now. Throws when the account is gone.
    func sender(for account: AccountID) throws -> Contact
}

/// Sends one account's due messages, oldest first.
public actor Sender {
    public nonisolated let accountID: AccountID
    private let provider: any MailProvider
    private let store: any OutgoingStore
    private let now: @Sendable () -> Date
    private var running: Task<[Draft], Never>?

    public init(
        accountID: AccountID,
        provider: any MailProvider,
        store: any OutgoingStore,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.accountID = accountID
        self.provider = provider
        self.store = store
        self.now = now
    }

    /// Sends, saves or deletes what is due. A refused message is marked failed and kept, for the writer to fix; a
    /// network failure, or an account that can't be read, leaves it queued for the next call. Who the mail is from is
    /// read as each message goes, so a renamed account's next message carries the new name. Returns the drafts the provider took.
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
                try? store.markFailed(message.id, reason: .forwardedAttachmentMissing)
                continue
            } catch {
                return sent
            }
            let from: Contact
            do {
                from = try store.sender(for: accountID)
            } catch {
                return sent
            }
            let raw = MIMEWriter.message(
                for: draft, from: from, date: now(),
                messageID: "\(message.id.uuidString.lowercased())@goodmail.app")
            do {
                switch message.purpose {
                case .send:
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
                try? store.markFailed(message.id, reason: .rejected)
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
