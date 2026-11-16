import Foundation
import MailCore

extension Draft {
    /// What a minimized message is called: its subject, else what kind of message it is.
    var shelfTitle: String {
        let subject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        if !subject.isEmpty { return subject }
        return inReplyTo == nil
            ? String(localized: "New Message", table: "Compose", bundle: .module, comment: "Composer title")
            : String(localized: "Reply", table: "Compose", bundle: .module, comment: "Composer title for a reply")
    }

    /// Who a minimized message goes to, by name where there is one. Empty before anyone is added.
    var shelfRecipients: String {
        (to + cc + bcc).map { $0.name ?? $0.address }.formatted(.list(type: .and, width: .short))
    }

    /// The start of what is written, for a laid-out draft.
    var shelfPreview: String {
        let text = (body.plain ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return String(text.prefix(400))
    }
}
