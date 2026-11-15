import MailCore
import UIKit

/// The mailbox toolbar's status between search and compose, as Mail shows an account error there: hidden while every
/// account syncs, otherwise the problem in two quiet lines. Tapping it asks to have each problem explained and fixed.
final class AccountProblemsItem {
    let item: UIBarButtonItem
    private let button: UIButton
    private var shown: [AccountProblemNotice] = []

    /// `tapped` hands over the notices shown when the status was tapped.
    init(tapped: @escaping ([AccountProblemNotice]) -> Void) {
        var configuration = UIButton.Configuration.plain()
        configuration.titleAlignment = .center
        configuration.baseForegroundColor = .secondaryLabel
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
            var attributes = $0
            attributes.font = UIFontMetrics(forTextStyle: .footnote).scaledFont(
                for: .systemFont(ofSize: 13, weight: .semibold))
            return attributes
        }
        configuration.subtitleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
            var attributes = $0
            attributes.font = UIFont.preferredFont(forTextStyle: .caption2)
            return attributes
        }
        button = UIButton(configuration: configuration)
        button.accessibilityIdentifier = "account-problems"
        item = UIBarButtonItem(customView: button)
        item.isHidden = true
        // An alert rather than a menu: a menu from this button was dismissed at once by a keyboard rising with no
        // field, while an alert holds the first responder for as long as it shows.
        button.addAction(UIAction { [unowned self] _ in tapped(shown) }, for: .primaryActionTriggered)
    }

    /// Shows `notices`. Only a change touches the button, as it lays the toolbar out again.
    func show(_ notices: [AccountProblemNotice]) {
        guard notices != shown else { return }
        shown = notices
        guard let summary = notices.summary else {
            item.isHidden = true
            return
        }
        button.configuration?.title = summary.title
        button.configuration?.subtitle = summary.subtitle
        item.isHidden = false
    }
}

extension UIAlertController {
    /// Each problem explained, with a button that fixes it: the only one's own, or one per account naming it.
    static func accountProblems(_ notices: [AccountProblemNotice], fix: @escaping (AccountProblemNotice) -> Void)
        -> UIAlertController
    {
        let alert = UIAlertController(
            title: notices.summary?.title, message: notices.map(\.message).joined(separator: "\n\n"),
            preferredStyle: .alert)
        for notice in notices {
            let title =
                notices.count == 1
                ? notice.fixTitle
                : String(
                    localized: "\(notice.fixTitle): \(notice.account.email)", table: "Health", bundle: .module,
                    comment: "Account problems alert: a fix and the account it is for, when there are several")
            alert.addAction(UIAlertAction(title: title, style: .default) { _ in fix(notice) })
        }
        alert.addAction(
            UIAlertAction(
                title: String(
                    localized: "Not Now", table: "Health", bundle: .module,
                    comment: "Button: closes the account problems without fixing them"),
                style: .cancel))
        if notices.count == 1 { alert.preferredAction = alert.actions.first }
        return alert
    }
}
