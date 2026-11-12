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

/// `users.threads.get` with `format=metadata` or `format=full`; `full` adds the MIME tree under `payload`.
struct GmailThread: Decodable {
    struct Message: Decodable {
        struct Payload: Decodable {
            struct Header: Decodable {
                let name: String
                let value: String
            }

            struct Body: Decodable {
                let size: Int?
                /// base64url, transfer encoding undone. Text arrives as UTF-8 whatever the part's declared charset.
                let data: String?
                let attachmentId: String?
            }

            let partId: String?
            let mimeType: String?
            let filename: String?
            let headers: [Header]?
            let body: Body?
            let parts: [Payload]?

            var mimePart: MIMEPart {
                MIMEPart(
                    partID: partId ?? "",
                    mimeType: mimeType ?? "application/octet-stream",
                    headers: (headers ?? []).map { ($0.name, $0.value) },
                    filename: filename ?? "",
                    data: body?.data.flatMap(Data.init(base64URLEncoded:)),
                    size: body?.size ?? 0,
                    fetchToken: body?.attachmentId,
                    parts: (parts ?? []).map(\.mimePart)
                )
            }
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

    /// The thread's messages, oldest first, for `format=full`.
    func messages(accountID: AccountID) -> [MailCore.Message] {
        (messages ?? [])
            .map { $0.message(accountID: accountID, threadID: id) }
            .sorted { $0.date < $1.date }
    }

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

extension GmailThread.Message {
    func message(accountID: AccountID, threadID: String) -> MailCore.Message {
        let content = payload?.mimePart.content() ?? (body: MessageBody(), attachments: [])
        // Gmail's copy of a sent message keeps its Bcc header too, but only a draft is shown it again.
        let isDraft = labelIds?.contains(SystemLabel.draft) == true
        return MailCore.Message(
            id: MailCore.Message.ID(accountID: accountID, messageID: id),
            threadID: threadID,
            from: Contact(parsing: header("From") ?? ""),
            to: Contact.list(parsing: header("To") ?? ""),
            cc: Contact.list(parsing: header("Cc") ?? ""),
            bcc: isDraft ? Contact.list(parsing: header("Bcc") ?? "") : [],
            replyTo: Contact.list(parsing: header("Reply-To") ?? ""),
            subject: header("Subject") ?? "",
            date: date ?? .distantPast,
            snippet: HTMLEntities.decode(snippet ?? ""),
            labelIDs: Set(labelIds ?? []),
            body: content.body,
            attachments: content.attachments,
            internetMessageID: header("Message-ID")?.trimmingCharacters(in: CharacterSet(charactersIn: "<> ")),
            references: (header("References") ?? "").split(whereSeparator: \.isWhitespace)
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "<>")) }
        )
    }
}

/// `users.messages.attachments.get`.
struct GmailAttachmentBody: Decodable {
    let data: String
}
