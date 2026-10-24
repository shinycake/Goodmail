import Foundation
import MailCore
import Observation

/// A message being written: its recipients, subject and body, and whether it can go.
@Observable
public final class ComposeViewModel {
    public private(set) var draft: Draft
    public let accountEmail: String
    /// The recipient fields as typed, parsed into contacts when sending.
    public var toText: String
    public var ccText: String
    public var bccText: String
    public var subject: String
    /// The files going with the message.
    public private(set) var attachments: [DraftAttachment]
    @ObservationIgnored private let sendAction: (Draft) -> Void
    @ObservationIgnored private let suggest: (String) -> [Contact]
    /// A draft that comes back with text, after Undo or a failed send, holds work closing would lose.
    @ObservationIgnored private let isRestored: Bool

    /// `send` queues the finished draft; the composer closes right after. `suggest` finds people for what is typed.
    public init(
        draft: Draft, accountEmail: String, suggest: @escaping (String) -> [Contact] = { _ in [] },
        send: @escaping (Draft) -> Void
    ) {
        self.draft = draft
        self.accountEmail = accountEmail
        toText = Self.text(draft.to)
        ccText = Self.text(draft.cc)
        bccText = Self.text(draft.bcc)
        subject = draft.subject
        attachments = draft.attachments
        sendAction = send
        self.suggest = suggest
        isRestored = !(draft.body.plain ?? "").isEmpty
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
        guard attachments.reduce(attachment.data.count, { $0 + $1.data.count }) <= Self.attachmentLimit else {
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
