import Foundation
import MailCore

/// One message as a printed page shows it: the conversation's subject over the first message, then who wrote to
/// whom and when, then the body as the reader shows it. Pure, so what goes on paper is testable.
nonisolated enum PrintDocument {
    /// The body's document (`MessageDocument`), with the message's headers leading its `<body>` and paper styles.
    static func html(
        for message: Message, subject: String?, dateText: String, allowsRemoteContent: Bool
    ) -> String {
        let document = MessageDocument.html(for: message.body, allowsRemoteContent: allowsRemoteContent)
        let withStyle = MessageDocument.inject(head: paperStyle, into: document)
        return inject(body: header(for: message, subject: subject, dateText: dateText), into: withStyle)
    }

    /// The headers block: the subject when given, then From, To, Cc and the date, each line reading its own way.
    static func header(for message: Message, subject: String?, dateText: String) -> String {
        func line(_ label: String, _ contacts: [Contact]) -> String {
            guard !contacts.isEmpty else { return "" }
            let names = contacts.map(Self.person).joined(separator: ", ")
            return #"<div dir="auto"><b>\#(MessageDocument.escape(label))</b> \#(MessageDocument.escape(names))</div>"#
        }
        let title = subject.map { #"<h1 dir="auto">\#(MessageDocument.escape($0))</h1>"# } ?? ""
        let from = String(localized: "From:", table: "Print", bundle: .module, comment: "Printed header label")
        let to = String(localized: "To:", table: "Print", bundle: .module, comment: "Printed header label")
        let cc = String(localized: "Cc:", table: "Print", bundle: .module, comment: "Printed header label")
        let date = String(localized: "Date:", table: "Print", bundle: .module, comment: "Printed header label")
        return #"<header class="goodmail-print">"# + title + line(from, [message.from]) + line(to, message.to)
            + line(cc, message.cc)
            + #"<div dir="auto"><b>\#(MessageDocument.escape(date))</b> \#(MessageDocument.escape(dateText))</div>"#
            + "</header>"
    }

    /// "Dana Levi <dana@example.com>", or the bare address when there is no name.
    static func person(_ contact: Contact) -> String {
        guard let name = contact.name, !name.isEmpty else { return contact.address }
        return "\(name) <\(contact.address)>"
    }

    /// Puts `html` first inside the document's `<body>`, or after its head when the sender left the tag out.
    static func inject(body html: String, into document: String) -> String {
        if let range = document.range(of: #"<body(\s[^>]*)?>"#, options: [.regularExpression, .caseInsensitive]) {
            return document.replacingCharacters(in: range, with: document[range] + html)
        }
        if let range = document.range(of: "</head>", options: .caseInsensitive) {
            return document.replacingCharacters(in: range, with: document[range] + html)
        }
        return html + document
    }

    /// Paper is white: dark mode's colors stay on screen.
    private static let paperStyle = """
        <style>\
        :root { color-scheme: light only; }\
        header.goodmail-print { font: 12px -apple-system; color: #000; margin-bottom: 16px; padding-bottom: 8px; \
        border-bottom: 1px solid #ccc; }\
        header.goodmail-print h1 { font: bold 20px ui-serif, "New York", serif; margin: 0 0 8px; }\
        header.goodmail-print div { margin: 2px 0; }\
        </style>
        """
}
