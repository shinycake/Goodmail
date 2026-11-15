import Foundation
import MailCore
import Observation

/// A message being written: its recipients, subject and body, and whether it can go.
@Observable
public final class ComposeViewModel {
    public private(set) var draft: Draft
    /// The address of the account the message goes from.
    public private(set) var accountEmail: String
    /// The accounts the message can go from, with their aliases.
    public let senders: [Account]
    /// The To, Cc and Bcc fields as the writer edits them: tokens, then what is still being typed.
    public var recipients: Recipients
    public var subject: String
    /// The files going with the message.
    public private(set) var attachments: [DraftAttachment]
    @ObservationIgnored private let sendAction: (Draft, SendTime) -> Void
    @ObservationIgnored private let saveAction: ((Draft) -> Void)?
    @ObservationIgnored private let deleteAction: (Draft) -> Void
    @ObservationIgnored private let signature: (AccountID) -> String?
    @ObservationIgnored private let suggest: (String) async -> [Contact]
    /// A draft that comes back with text, after Undo or a failed send, holds work closing would lose.
    @ObservationIgnored let isRestored: Bool

    /// `send` queues the finished draft to go now or later; the composer closes right after. `saveDraft` keeps it in the provider's
    /// Drafts and `deleteDraft` removes the copy it was opened from. `suggest` finds people for what is typed. A new
    /// draft starts with its account's `signature` below the line being written.
    public init(
        draft: Draft, accountEmail: String, senders: [Account] = [],
        signature: @escaping (AccountID) -> String? = { _ in nil },
        suggest: @escaping (String) async -> [Contact] = { _ in [] }, saveDraft: ((Draft) -> Void)? = nil,
        deleteDraft: @escaping (Draft) -> Void = { _ in }, send: @escaping (Draft, SendTime) -> Void
    ) {
        let isNew = (draft.body.plain ?? "").isEmpty
        // A draft opened from the provider's Drafts is safe there until it changes.
        isRestored = !isNew && draft.savedDraft == nil
        var draft = draft
        if isNew { draft.body = Self.startingBody(signature: signature(draft.accountID)) }
        self.draft = draft
        self.accountEmail = accountEmail
        self.senders = senders
        self.signature = signature
        recipients = Recipients(to: draft.to, cc: draft.cc, bcc: draft.bcc)
        subject = draft.subject
        attachments = draft.attachments
        sendAction = send
        saveAction = saveDraft
        deleteAction = deleteDraft
        self.suggest = suggest
    }

    /// Every typed recipient looks like an address, and there is at least one.
    public var canSend: Bool {
        let all = recipients.all
        return !all.isEmpty && all.allSatisfy(\.hasValidAddress)
    }

    public var isReply: Bool { draft.inReplyTo != nil }

    /// Whether closing would lose anything the writer did, formatting included.
    public func hasChanges(body: MessageBody) -> Bool {
        let edited = finished(body: body)
        return isRestored || edited.to != draft.to || edited.cc != draft.cc || edited.bcc != draft.bcc
            || edited.subject != draft.subject || RichText(body) != RichText(draft.body)
            || edited.attachments != draft.attachments
    }

    /// Gmail refuses messages over 25 MB, and encoding the files adds a third.
    static let attachmentLimit = 18_000_000

    /// Adds the file unless it would take the message past what Gmail accepts. Returns whether it was added.
    @discardableResult
    public func attach(_ attachment: DraftAttachment) -> Bool {
        guard attachments.reduce(attachment.size, { $0 + $1.size }) <= Self.attachmentLimit else {
            return false
        }
        attachments.append(attachment)
        return true
    }

    public func removeAttachment(_ id: DraftAttachment.ID) {
        attachments.removeAll { $0.id == id }
    }

    /// Queues the message with `body` as written, to go at `time`. Does nothing while `canSend` is false.
    public func send(body: MessageBody, at time: SendTime = .now) {
        guard canSend else { return }
        sendAction(finished(body: body), time)
    }

    public var canSaveDraft: Bool { saveAction != nil }

    /// The addresses the message can go from: any account's or alias for new mail; a reply, forward or saved
    /// draft stays in its own account.
    public var senderChoices: [SendingAddress] { SendingAddress.choices(for: draft, among: senders) }

    public var canChangeSender: Bool { senderChoices.count > 1 }

    /// The address the message goes from: its alias, else its account's own.
    public var fromAddress: String { draft.alias?.address ?? accountEmail }

    /// Sends from `address` instead. While the body is still as it started, its signature follows a change of
    /// account: returns the new body to show then, `nil` when the body stays.
    public func changeSender(to address: SendingAddress, body: MessageBody) -> MessageBody? {
        let untouched = RichText(body) == RichText(draft.body)
        let changesAccount = address.account.id != draft.accountID
        draft.accountID = address.account.id
        draft.alias = address.alias
        accountEmail = address.account.email
        guard changesAccount, untouched else { return nil }
        draft.body = Self.startingBody(signature: signature(address.account.id))
        return draft.body
    }

    private static func startingBody(signature: String?) -> MessageBody {
        guard let signature, !signature.isEmpty else { return MessageBody(html: "", plain: "") }
        return MessageBody(html: nil, plain: "\n\n-- \n" + signature)
    }

    /// Keeps the message as written in the provider's Drafts.
    public func saveDraft(body: MessageBody) {
        saveAction?(finished(body: body))
    }

    /// Throws the message away, with the provider's copy when it was opened from one.
    public func deleteDraft() {
        deleteAction(draft)
    }

    func finished(body: MessageBody) -> Draft {
        var draft = draft
        draft.to = recipients.to.all
        draft.cc = recipients.cc.all
        draft.bcc = recipients.bcc.all
        draft.subject = subject
        draft.body = body
        draft.attachments = attachments
        return draft
    }

    /// People to offer for what is typed in the `role` field, leaving out those already in it and the addresses the
    /// message can go from.
    public func suggestions(for role: Recipients.Role) async -> [Contact] {
        let entry = recipients[role]
        let typed = entry.typed.trimmingCharacters(in: .whitespaces)
        guard !typed.isEmpty else { return [] }
        let excluded = Set(
            (entry.contacts.map(\.address) + senders.flatMap { [$0.email] + $0.aliases.map(\.address) }
                + [accountEmail]).map { $0.lowercased() })
        return await suggest(typed).filter { !excluded.contains($0.address.lowercased()) }
    }
}
