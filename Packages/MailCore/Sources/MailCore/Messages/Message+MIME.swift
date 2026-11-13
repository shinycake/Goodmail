import Foundation

extension Message {
    /// A message read from its MIME tree: its people, subject and threading headers from the top-level headers,
    /// and its body and attachments as `MIMEPart.content()` picks them. What a provider keeps outside the message,
    /// its date, snippet and labels, comes in alongside.
    public init(id: ID, threadID: String, mime: MIMEPart, date: Date, snippet: String, labelIDs: Set<String>) {
        let content = mime.content()
        func header(_ name: String) -> String { mime.header(name) ?? "" }
        self.init(
            id: id,
            threadID: threadID,
            from: Contact(parsing: header("From")),
            to: Contact.list(parsing: header("To")),
            cc: Contact.list(parsing: header("Cc")),
            // A service's copy of a sent message may keep its Bcc header too, but only a draft is shown it again.
            bcc: labelIDs.contains(SystemLabel.draft) ? Contact.list(parsing: header("Bcc")) : [],
            replyTo: Contact.list(parsing: header("Reply-To")),
            subject: header("Subject"),
            date: date,
            snippet: snippet,
            labelIDs: labelIDs,
            body: content.body,
            attachments: content.attachments,
            internetMessageID: Self.messageIDs(in: header("Message-ID")).first,
            references: Self.messageIDs(in: header("References"))
        )
    }

    /// Every `<...>` in a header, without its brackets, so folding, missing spaces and stray comments don't matter.
    static func messageIDs(in header: String) -> [String] {
        header.matches(of: /<([^<>\s]+)>/).map { String($0.output.1) }
    }
}
