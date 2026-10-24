import Foundation
import MailCore

/// `users.getProfile`.
struct GmailProfile: Decodable {
    let historyId: String
}

/// `users.history.list`. Every record lists the messages it touched in `messages`, whatever its type.
struct GmailHistoryList: Decodable {
    struct Record: Decodable {
        struct MessageRef: Decodable {
            let threadId: String
        }

        struct Change: Decodable {
            let message: MessageRef
        }

        let messages: [MessageRef]?
        let messagesAdded: [Change]?
        let messagesDeleted: [Change]?
        let labelsAdded: [Change]?
        let labelsRemoved: [Change]?

        var threadIDs: [String] {
            let changes = [messagesAdded, messagesDeleted, labelsAdded, labelsRemoved].compactMap(\.self).joined()
            return (messages ?? []).map(\.threadId) + changes.map(\.message.threadId)
        }
    }

    let history: [Record]?
    let historyId: String
    let nextPageToken: String?
}

/// `users.labels.list`.
struct GmailLabelList: Decodable {
    struct Label: Decodable {
        struct Color: Decodable {
            let backgroundColor: String?
        }

        let id: String
        let name: String
        let type: String?
        let labelListVisibility: String?
        let color: Color?

        var mailLabel: MailLabel {
            MailLabel(
                id: id,
                name: name,
                kind: type == "user" ? .user : .system,
                color: color?.backgroundColor,
                isHidden: labelListVisibility == "labelHide"
            )
        }
    }

    let labels: [Label]?
}

extension ThreadQuery {
    /// Gmail search terms for the date bounds. `after:` and `before:` accept epoch seconds.
    var gmailSearch: String? {
        let terms = [
            since.map { "after:\(Int($0.timeIntervalSince1970))" },
            before.map { "before:\(Int($0.timeIntervalSince1970))" },
        ]
        .compactMap(\.self)
        return terms.isEmpty ? nil : terms.joined(separator: " ")
    }
}
