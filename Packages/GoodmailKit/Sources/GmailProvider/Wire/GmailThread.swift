import Foundation
import MailCore

/// `users.threads.list` response.
struct ThreadList: Decodable {
    struct Entry: Decodable {
        let id: String
    }

    let threads: [Entry]?
    let nextPageToken: String?
}

/// `users.threads.get` with `format=metadata`.
struct GmailThread: Decodable {
    struct Message: Decodable {
        struct Payload: Decodable {
            struct Header: Decodable {
                let name: String
                let value: String
            }

            let headers: [Header]?
        }

        let id: String
        let labelIds: [String]?
        let snippet: String?
        let internalDate: String?
        let payload: Payload?

        func header(_ name: String) -> String? {
            payload?.headers?.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
        }

        var date: Date? {
            internalDate.flatMap(Double.init).map { Date(timeIntervalSince1970: $0 / 1000) }
        }
    }

    let id: String
    let messages: [Message]?

    /// `nil` for a thread with no messages, which Gmail can briefly return after a delete.
    func summary(accountID: AccountID) -> ThreadSummary? {
        guard let messages, let latest = messages.max(by: { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) })
        else { return nil }

        let labels = Set(messages.flatMap { $0.labelIds ?? [] })
        return ThreadSummary(
            id: ThreadSummary.ID(accountID: accountID, threadID: id),
            subject: messages.first?.header("Subject") ?? "",
            snippet: HTMLEntities.decode(latest.snippet ?? ""),
            sender: Contact(parsing: latest.header("From") ?? ""),
            date: latest.date ?? .distantPast,
            isUnread: messages.contains { $0.labelIds?.contains("UNREAD") == true },
            messageCount: messages.count,
            labelIDs: labels.subtracting(["UNREAD"])
        )
    }
}

extension Contact {
    /// Parses an RFC 5322 mailbox as Gmail returns it, already MIME-decoded: `"Name" <a@b.c>`, `Name <a@b.c>` or `a@b.c`.
    init(parsing header: String) {
        let trimmed = header.trimmingCharacters(in: .whitespaces)
        guard let open = trimmed.lastIndex(of: "<"), let close = trimmed.lastIndex(of: ">"), open < close else {
            self.init(name: nil, address: trimmed)
            return
        }
        let address = String(trimmed[trimmed.index(after: open)..<close])
        let name = trimmed[..<open]
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        self.init(name: name.isEmpty ? nil : name, address: address)
    }
}
