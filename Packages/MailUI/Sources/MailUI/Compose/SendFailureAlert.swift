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
            ? String(localized: "(No Subject)", bundle: .module, comment: "Shown in place of an empty email subject")
            : message.draft.subject
        let alert = UIAlertController(
            title: String(
                localized: "Couldn't Send “\(subject)”", bundle: .module, comment: "A message failed to send"),
            message: message.failure, preferredStyle: .alert)
        alert.addAction(
            UIAlertAction(
                title: String(localized: "Edit", bundle: .module, comment: "Reopens a failed message"),
                style: .default
            ) { _ in edit() })
        alert.addAction(
            UIAlertAction(
                title: String(localized: "Try Again", bundle: .module, comment: "Sends a failed message again"),
                style: .default
            ) { _ in retry() })
        alert.addAction(
            UIAlertAction(
                title: String(localized: "Delete", bundle: .module, comment: "Deletes a failed message"),
                style: .destructive
            ) { _ in delete() })
        return alert
    }
}
