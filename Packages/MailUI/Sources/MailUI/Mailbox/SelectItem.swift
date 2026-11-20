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
    /// With `bar` on screen, the button morphs in and out of the glass it shares with Search: the change and the bar's
    /// new layout go in one spring, so the capsule shrinks into Search's circle (and grows back out of it) rather than
    /// jumping.
    func show(rows: Int, in bar: UINavigationBar? = nil) {
        let hidden = rows == 0
        guard hidden != item.isHidden else { return }
        guard let bar, bar.window != nil else {
            item.isHidden = hidden
            return
        }
        bar.layoutIfNeeded()
        UIView.animate(springDuration: Self.morph, bounce: 0.15) { [item] in
            item.isHidden = hidden
            bar.layoutIfNeeded()
        }
    }

    /// How long the morph's spring runs.
    static let morph: TimeInterval = 0.45
}
