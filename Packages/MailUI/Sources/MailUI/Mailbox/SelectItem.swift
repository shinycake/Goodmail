import UIKit

/// The mailbox's Select button: a checklist that reads "Select" to VoiceOver, in the large-content viewer and in the
/// More menu, there only while the list has threads to select.
final class SelectItem {
    let item: UIBarButtonItem

    /// `begin` starts selecting.
    init(begin: @escaping () -> Void) {
        item = UIBarButtonItem(
            title: String(
                localized: "Select", table: "Mailbox", bundle: .module, comment: "Starts selecting several threads"),
            image: UIImage(systemName: "checklist"),
            primaryAction: UIAction { _ in begin() })
        item.accessibilityLabel = item.title
        // A list starts with no rows; it shows once some come in.
        item.isHidden = true
    }

    /// Shows the button for a list of `rows` rows. Only a change touches the button, as it lays the bar out again.
    func show(rows: Int) {
        let hidden = rows == 0
        if hidden != item.isHidden { item.isHidden = hidden }
    }
}
