import Foundation

/// A conversation as plain text: its subject, then each message's From, To, Cc and date over its body, with a
/// rule between messages. HTML-only bodies become their words.
public enum ConversationText {
    /// The header labels, in the reader's language.
    public struct Labels: Sendable {
        public let from: String
        public let to: String
        public let cc: String
        public let date: String

        public init(from: String, to: String, cc: String, date: String) {
            self.from = from
            self.to = to
            self.cc = cc
            self.date = date
        }
    }

    public static func text(
        for messages: [Message], subject: String, labels: Labels, dateText: (Message) -> String
    ) -> String {
        let parts = messages.map { message in
            let headers = [
                line(labels.from, [message.from]), line(labels.to, message.to), line(labels.cc, message.cc),
                "\(labels.date) \(dateText(message))",
            ].compactMap { $0 }
            return headers.joined(separator: "\n") + "\n\n" + body(of: message) + "\n"
        }
        return subject + "\n\n" + parts.joined(separator: "\n――――――――――\n\n")
    }

    private static func line(_ label: String, _ contacts: [Contact]) -> String? {
        guard !contacts.isEmpty else { return nil }
        return label + " " + contacts.map(person).joined(separator: ", ")
    }

    /// "Dana Levi <dana@example.com>", or the bare address when there is no name.
    public static func person(_ contact: Contact) -> String {
        guard let name = contact.name, !name.isEmpty else { return contact.address }
        return "\(name) <\(contact.address)>"
    }

    private static func body(of message: Message) -> String {
        if let plain = message.body.plain, !plain.isEmpty {
            return plain.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let html = message.body.html { return HTMLEntities.plainText(fromHTML: html) }
        return message.snippet
    }
}
