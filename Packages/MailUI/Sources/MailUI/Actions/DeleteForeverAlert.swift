import UIKit

/// What a Delete Forever confirmation asks about.
enum DeleteForeverScope: Equatable {
    /// Threads the reader picked.
    case threads(Int)
    /// Every thread the Trash list holds.
    case trash(Int)
}

extension UIAlertController {
    /// Asks before deleting threads for good, which nothing undoes. `confirm` runs only on Delete Forever.
    static func deleteForever(_ scope: DeleteForeverScope, confirm: @escaping () -> Void) -> UIAlertController {
        let title: String
        let message: String
        switch scope {
        case .threads(let count):
            title = String(
                localized: "Delete \(count) Threads Forever?", table: "DeleteForever", bundle: .module,
                comment: "Title of the alert before deleting threads in Trash for good")
            message = String(
                localized: "You can’t undo this.", table: "DeleteForever", bundle: .module,
                comment: "Message of the alert before deleting threads in Trash for good")
        case .trash(let count):
            title = String(
                localized: "Empty Trash?", table: "DeleteForever", bundle: .module,
                comment: "Title of the alert before emptying Trash")
            message = String(
                localized: "All \(count) threads in Trash will be deleted. You can’t undo this.",
                table: "DeleteForever", bundle: .module,
                comment: "Message of the alert before emptying Trash, with how many it deletes")
        }
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(
            UIAlertAction(
                title: String(
                    localized: "Cancel", table: "DeleteForever", bundle: .module, comment: "Button: keeps the threads"),
                style: .cancel))
        let delete = UIAlertAction(title: scope.actionTitle, style: .destructive) { _ in confirm() }
        alert.addAction(delete)
        return alert
    }
}

extension DeleteForeverScope {
    /// The alert's destructive button, which says what it does.
    var actionTitle: String {
        switch self {
        case .threads:
            String(
                localized: "Delete Forever", table: "DeleteForever", bundle: .module,
                comment: "Action: delete a thread in Trash for good")
        case .trash:
            String(
                localized: "Empty Trash", table: "DeleteForever", bundle: .module,
                comment: "Action: delete everything in Trash for good")
        }
    }
}
