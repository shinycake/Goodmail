import MailCore
import UIKit

/// Tells the writer a message couldn't be sent, and offers to edit it, try again, or delete it.
public enum SendFailureAlert {
    public static func make(
        for message: OutgoingMessage,
        edit: @escaping () -> Void,
        retry: @escaping () -> Void,
        delete: @escaping () -> Void
    ) -> UIAlertController {
        let subject =
            message.draft.subject.isEmpty
            ? String(
                localized: "(No Subject)", table: "Compose", bundle: .module,
                comment: "Shown in place of an empty email subject")
            : message.draft.subject
        let alert = UIAlertController(
            title: String(
                localized: "Couldn't Send “\(subject)”", table: "Compose", bundle: .module,
                comment: "A message failed to send"),
            message: message.failure?.explanation, preferredStyle: .alert)
        alert.addAction(
            UIAlertAction(
                title: String(
                    localized: "Edit", table: "Compose", bundle: .module, comment: "Reopens a failed message"),
                style: .default
            ) { _ in edit() })
        alert.addAction(
            UIAlertAction(
                title: String(
                    localized: "Try Again", table: "Compose", bundle: .module, comment: "Sends a failed message again"),
                style: .default
            ) { _ in retry() })
        alert.addAction(
            UIAlertAction(
                title: String(
                    localized: "Delete", table: "Compose", bundle: .module, comment: "Deletes a failed message"),
                style: .destructive
            ) { _ in delete() })
        return alert
    }
}

extension SendFailure {
    /// Why the message didn't go, in the reader's language.
    var explanation: String {
        switch self {
        case .forwardedAttachmentMissing:
            String(
                localized: "A forwarded attachment is no longer available.", table: "Compose", bundle: .module,
                comment: "Why a message failed to send: a file it forwards is gone")
        case .rejected:
            String(
                localized: "The server refused the message.", table: "Compose", bundle: .module,
                comment: "Why a message failed to send: the mail server refused it")
        case .unconfirmed:
            String(
                localized: "Goodmail couldn’t confirm it was sent. Check Sent before trying again.", table: "Compose",
                bundle: .module,
                comment: "Why a message failed to send: its upload ended without an answer and it isn't in Sent")
        }
    }
}
