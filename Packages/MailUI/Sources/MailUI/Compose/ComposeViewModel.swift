import Foundation
import MailCore
import Observation

/// A message being written: its recipients, subject and body, and whether it can go.
@Observable
public final class ComposeViewModel {
    public private(set) var draft: Draft
    public private(set) var accountEmail: String
    /// The accounts the message can go from.
    public let senders: [Account]
    /// The recipient fields as typed, parsed into contacts when sending.
    public var toText: String
    public var ccText: String
    public var bccText: String
    public var subject: String
    /// The files going with the message.
    public private(set) var attachments: [DraftAttachment]
    @ObservationIgnored private let sendAction: (Draft) -> Void
    @ObservationIgnored private let saveAction: ((Draft) -> Void)?
    @ObservationIgnored private let deleteAction: (Draft) -> Void
    @ObservationIgnored private let signature: (AccountID) -> String?
    @ObservationIgnored private let suggest: (String) -> [Contact]
    /// A draft that comes back with text, after Undo or a failed send, holds work closing would lose.
    @ObservationIgnored let isRestored: Bool

    /// `send` queues the finished draft; the composer closes right after. `saveDraft` keeps it in the provider's
    /// Drafts and `deleteDraft` removes the copy it was opened from. `suggest` finds people for what is typed. A new
    /// draft starts with its account's `signature` below the line being written.
    public init(
        draft: Draft, accountEmail: String, senders: [Account] = [],
        signature: @escaping (AccountID) -> String? = { _ in nil },
        suggest: @escaping (String) -> [Contact] = { _ in [] }, saveDraft: ((Draft) -> Void)? = nil,
        deleteDraft: @escaping (Draft) -> Void = { _ in }, send: @escaping (Draft) -> Void
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
        toText = Self.text(draft.to)
        ccText = Self.text(draft.cc)
        bccText = Self.text(draft.bcc)
        subject = draft.subject
        attachments = draft.attachments
        sendAction = send
        saveAction = saveDraft
        deleteAction = deleteDraft
        self.suggest = suggest
    }

    /// Every typed recipient looks like an address, and there is at least one.
    public var canSend: Bool {
        let all = [toText, ccText, bccText].flatMap(Contact.list(parsing:))
        return !all.isEmpty && all.allSatisfy { Self.isAddress($0.address) }
    }

    public var isReply: Bool { draft.inReplyTo != nil }

    /// Whether closing would lose anything the writer did.
    public func hasChanges(body: MessageBody) -> Bool {
        let edited = finished(body: body)
        return isRestored || edited.to != draft.to || edited.cc != draft.cc || edited.bcc != draft.bcc
            || edited.subject != draft.subject || (body.plain ?? "") != (draft.body.plain ?? "")
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

    /// Queues the message with `body` as written. Does nothing while `canSend` is false.
    public func send(body: MessageBody) {
        guard canSend else { return }
        sendAction(finished(body: body))
    }

    public var canSaveDraft: Bool { saveAction != nil }

    /// A new message can go from any account; a reply, forward or saved draft stays in its own.
    public var canChangeSender: Bool {
        senders.count > 1 && draft.threadID == nil && draft.savedDraft == nil
    }

    /// Sends from `account` instead. While the body is still as it started, its signature follows the account:
    /// returns the new body to show then, `nil` when the writer's text stays.
    public func changeSender(to account: Account, body: MessageBody) -> MessageBody? {
        let untouched = (body.plain ?? "") == (draft.body.plain ?? "")
        draft.accountID = account.id
        accountEmail = account.email
        guard untouched else { return nil }
        draft.body = Self.startingBody(signature: signature(account.id))
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
        draft.to = Contact.list(parsing: toText)
        draft.cc = Contact.list(parsing: ccText)
        draft.bcc = Contact.list(parsing: bccText)
        draft.subject = subject
        draft.body = body
        draft.attachments = attachments
        return draft
    }

    /// People to offer for the recipient being typed at the end of `field`, leaving out those already in it.
    public func suggestions(for field: String) -> [Contact] {
        let typed = field[Self.lastEntryStart(in: field)...].trimmingCharacters(in: .whitespaces)
        guard !typed.isEmpty else { return [] }
        let entered = Set(Contact.list(parsing: field).map { $0.address.lowercased() })
        return suggest(typed).filter { !entered.contains($0.address.lowercased()) }
    }

    /// `field` with the recipient being typed replaced by `contact`, ready for the next one.
    public static func completing(_ field: String, with contact: Contact) -> String {
        let kept = field[..<lastEntryStart(in: field)]
        return (kept.isEmpty ? "" : kept + " ") + text([contact]) + ", "
    }

    /// Where the last recipient starts: after the last comma that isn't inside quotes or angle brackets.
    private static func lastEntryStart(in field: String) -> String.Index {
        var start = field.startIndex
        var inQuotes = false
        var inAngles = false
        for index in field.indices {
            switch field[index] {
            case "\"": inQuotes.toggle()
            case "<" where !inQuotes: inAngles = true
            case ">" where !inQuotes: inAngles = false
            case "," where !inQuotes && !inAngles: start = field.index(after: index)
            default: break
            }
        }
        return start
    }

    static func text(_ contacts: [Contact]) -> String {
        contacts.map { contact in
            guard let name = contact.name, !name.isEmpty else { return contact.address }
            let quoted = name.contains(",") ? "\"\(name)\"" : name
            return "\(quoted) <\(contact.address)>"
        }
        .joined(separator: ", ")
    }

    static func isAddress(_ text: String) -> Bool {
        let parts = text.split(separator: "@", omittingEmptySubsequences: false)
        return parts.count == 2 && !parts[0].isEmpty && parts[1].contains(".") && !text.contains(" ")
            && !parts[1].hasPrefix(".") && !parts[1].hasSuffix(".")
    }
}
