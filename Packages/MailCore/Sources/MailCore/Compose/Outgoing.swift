import Foundation

/// A message queued for the provider: to send once the undo window closes, or to keep in its drafts.
public struct OutgoingMessage: Identifiable, Equatable, Sendable {
    public enum Purpose: String, Codable, Sendable {
        case send
        /// Sends at a time the writer picked, which may be days away. Listed under Scheduled until it goes.
        case scheduledSend
        /// Saves the draft with the provider, replacing its earlier saved copy.
        case saveDraft
        /// Removes the draft's saved copy.
        case deleteDraft
    }

    /// Where the message is on its way. A message that went is no longer queued at all.
    public enum Delivery: Equatable, Sendable {
        /// Waiting for its undo window to close, or for the next attempt. Only now can it be taken back.
        case queued
        /// Handed to a transfer that outlives the app; its outcome is still to come.
        case uploading(UploadID)
        /// Failed for good, until the writer edits it, tries again or deletes it.
        case failed(SendFailure)
    }

    public var id: Draft.ID { draft.id }
    public var draft: Draft
    public var purpose: Purpose
    /// When the message may go: when its undo window closes, or at its scheduled time.
    public var sendAt: Date
    public var delivery: Delivery

    public init(draft: Draft, purpose: Purpose = .send, sendAt: Date, delivery: Delivery = .queued) {
        self.draft = draft
        self.purpose = purpose
        self.sendAt = sendAt
        self.delivery = delivery
    }

    /// The `Message-ID` it goes out with, the same on every attempt, so the provider can say whether it went.
    public var headerID: String { "\(id.uuidString.lowercased())@goodmail.app" }

    /// The failure shown to the writer, or `nil` while it is still on its way.
    public var failure: SendFailure? {
        if case .failed(let failure) = delivery { failure } else { nil }
    }

    func with(_ delivery: Delivery) -> OutgoingMessage {
        var message = self
        message.delivery = delivery
        return message
    }
}

/// Why a queued message failed for good. Stored as its raw value and worded by the UI in the reader's language.
public enum SendFailure: String, Sendable {
    /// A file forwarded from another message is gone from the server.
    case forwardedAttachmentMissing
    /// The server refused the message.
    case rejected
    /// Its upload ended without an answer, and it isn't among the sent mail. It may still have gone, so it is not
    /// sent again without the writer.
    case unconfirmed
}

/// The persistence the send queue needs. `MailStore` implements it.
public protocol OutgoingStore: Sendable {
    func enqueue(_ message: OutgoingMessage) throws
    /// Removes a message that is still queued. Returns it, or `nil` when it already went or is going.
    func cancel(_ id: Draft.ID) throws -> OutgoingMessage?
    /// Gives a message that is still queued a new purpose and time, in one write. Returns it changed, or `nil` when
    /// it already went or is going.
    func requeue(_ id: Draft.ID, as purpose: OutgoingMessage.Purpose, at date: Date) throws -> OutgoingMessage?
    /// Queued messages due by `date`, oldest first.
    func dueMessages(for account: AccountID, by date: Date) throws -> [OutgoingMessage]
    /// The earliest time a queued message falls due.
    func nextSendDate(for account: AccountID) throws -> Date?
    /// Messages handed to an upload whose outcome hasn't been taken in.
    func uploadingMessages(for account: AccountID) throws -> [OutgoingMessage]
    /// Replaces message `id` with `message`, or removes it when `message` is `nil`, only while its delivery is
    /// still `expected`. Returns whether it was. Every step of a delivery goes through here, so a step that lost a
    /// race (an undo, a second launch, a late outcome) changes nothing.
    func update(_ id: Draft.ID, from expected: OutgoingMessage.Delivery, to message: OutgoingMessage?) throws -> Bool
    func remove(_ id: Draft.ID) throws
    /// Who the account's mail is from now. Throws when the account is gone.
    func sender(for account: AccountID) throws -> Contact
}
