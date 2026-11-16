import Foundation

/// A message as a shortcut or Siri writes it: recipients as typed text, a subject, plain text and files. It fills a
/// new message, a reply or a forward (`Draft.add(_:)`).
public struct WrittenMail: Equatable, Sendable {
    /// Each entry is one address or a list of them, separated by commas or semicolons, as `Name <a@b.c>` or bare.
    public var to: [String]
    public var cc: [String]
    public var bcc: [String]
    /// `nil` keeps the subject the draft has, as a reply's "Re:".
    public var subject: String?
    public var text: String
    public var attachments: [DraftAttachment]

    public init(
        to: [String] = [], cc: [String] = [], bcc: [String] = [], subject: String? = nil, text: String = "",
        attachments: [DraftAttachment] = []
    ) {
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.subject = subject
        self.text = text
        self.attachments = attachments
    }
}

/// Why written mail can't go.
public enum WrittenMailError: Error, Equatable, Sendable {
    /// A recipient that doesn't read as an email address, as typed.
    case notAnAddress(String)
    /// A message with no one to send it to.
    case noRecipients
}

extension Draft {
    /// Adds what was written: its recipients after the draft's own, its subject in place of the draft's when it
    /// gives one, its text as the body above any quote, and its files after the draft's. Throws for a recipient
    /// that isn't an address, leaving the draft as it was.
    public mutating func add(_ mail: WrittenMail) throws(WrittenMailError) {
        let (to, cc, bcc) = (try Self.contacts(mail.to), try Self.contacts(mail.cc), try Self.contacts(mail.bcc))
        self.to += to
        self.cc += cc
        self.bcc += bcc
        if let subject = mail.subject?.trimmingCharacters(in: .whitespacesAndNewlines), !subject.isEmpty {
            self.subject = subject
        }
        if !mail.text.isEmpty { body = MessageBody(html: HTMLText.lines(mail.text), plain: mail.text) }
        attachments += mail.attachments
    }

    /// Throws unless the draft can go: someone to send it to, each an address.
    public func checkReadyToSend() throws(WrittenMailError) {
        guard !recipients.isEmpty else { throw .noRecipients }
        if let wrong = recipients.first(where: { !$0.hasValidAddress }) { throw .notAnAddress(wrong.typedForm) }
    }

    /// The contacts the entries name, in order.
    private static func contacts(_ entries: [String]) throws(WrittenMailError) -> [Contact] {
        var contacts: [Contact] = []
        for entry in entries {
            for contact in Contact.list(parsing: entry.replacing(/[;\n]/, with: ",")) {
                guard contact.hasValidAddress else { throw .notAnAddress(contact.typedForm) }
                contacts.append(contact)
            }
        }
        return contacts
    }
}
