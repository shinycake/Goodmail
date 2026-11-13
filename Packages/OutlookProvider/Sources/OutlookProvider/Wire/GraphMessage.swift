import Foundation
import MailCore

/// A message as Graph lists it, with the properties a thread summary needs.
struct GraphMessage: Decodable {
    struct Recipient: Decodable {
        struct Address: Decodable {
            let name: String?
            let address: String?
        }

        let emailAddress: Address?

        var contact: Contact? {
            guard let address = emailAddress?.address, !address.isEmpty else { return nil }
            return Contact(name: emailAddress?.name, address: address)
        }
    }

    struct Flag: Decodable {
        let flagStatus: String?
    }

    /// What `$select` asks for, so lists carry exactly what `summary` reads.
    static let summaryFields = "id,conversationId,subject,bodyPreview,from,receivedDateTime,isRead,flag,parentFolderId"

    let id: String
    let conversationId: String?
    let subject: String?
    let bodyPreview: String?
    let from: Recipient?
    let receivedDateTime: Date?
    let isRead: Bool?
    let flag: Flag?
    let parentFolderId: String?

    /// The folder's label, then Unread and Starred, which Outlook keeps as flags on the message.
    func labelIDs(in folders: FolderDirectory) -> Set<String> {
        var labels: Set<String> = []
        if let folder = parentFolderId, let label = folders.label(forFolder: folder) { labels.insert(label) }
        if isRead == false { labels.insert(SystemLabel.unread) }
        if isFlagged { labels.insert(SystemLabel.starred) }
        return labels
    }
}

extension ThreadSummary {
    /// A conversation's summary from its messages, in any order: the latest one speaks for it, and it carries every
    /// message's labels, as a Gmail thread does. `nil` for no messages.
    init?(conversation id: ID, messages: [GraphMessage], folders: FolderDirectory) {
        let ordered = messages.sorted { ($0.receivedDateTime ?? .distantPast) < ($1.receivedDateTime ?? .distantPast) }
        guard let latest = ordered.last else { return nil }
        let labels = ordered.reduce(into: Set<String>()) { $0.formUnion($1.labelIDs(in: folders)) }
        self.init(
            id: id,
            subject: ordered.first { !($0.subject ?? "").isEmpty }?.subject ?? "",
            snippet: latest.bodyPreview ?? "",
            sender: latest.from?.contact ?? Contact(name: nil, address: ""),
            date: latest.receivedDateTime ?? .distantPast,
            isUnread: labels.contains(SystemLabel.unread),
            messageCount: ordered.count,
            // Unread is the summary's flag, not one of its labels, as in Gmail's summaries and the store.
            labelIDs: labels.subtracting([SystemLabel.unread])
        )
    }
}
