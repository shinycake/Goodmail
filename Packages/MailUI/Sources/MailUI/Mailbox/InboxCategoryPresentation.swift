import MailCore
import UIKit

extension InboxCategory {
    public var title: String {
        switch self {
        case .primary:
            String(
                localized: "InboxCategory.Primary", defaultValue: "Primary", table: "Mailbox", bundle: .module,
                comment: "Inbox category: personal mail and anything Gmail didn't sort")
        case .promotions:
            String(
                localized: "InboxCategory.Promotions", defaultValue: "Promotions", table: "Mailbox", bundle: .module,
                comment: "Inbox category: deals and offers")
        case .social:
            String(
                localized: "InboxCategory.Social", defaultValue: "Social", table: "Mailbox", bundle: .module,
                comment: "Inbox category: social networks")
        case .updates:
            String(
                localized: "InboxCategory.Updates", defaultValue: "Updates", table: "Mailbox", bundle: .module,
                comment: "Inbox category: receipts, bills and notifications")
        case .forums:
            String(
                localized: "InboxCategory.Forums", defaultValue: "Forums", table: "Mailbox", bundle: .module,
                comment: "Inbox category: mailing lists and groups")
        }
    }

    var symbol: String {
        switch self {
        case .primary: "tray"
        case .promotions: "tag"
        case .social: "person.2"
        case .updates: "info.circle"
        case .forums: "bubble.left.and.bubble.right"
        }
    }
}

extension MailboxViewController {
    /// The compact "Primary ▾" pill that switches the Inbox's category.
    static func categoryButton() -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(
            systemName: "chevron.down",
            withConfiguration: UIImage.SymbolConfiguration(textStyle: .footnote, scale: .small)
                .applying(UIImage.SymbolConfiguration(weight: .semibold)))
        configuration.imagePlacement = .trailing
        configuration.imagePadding = 4
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
                for: .systemFont(ofSize: 15, weight: .semibold))
            return attributes
        }
        let button = UIButton(configuration: configuration)
        button.showsMenuAsPrimaryAction = true
        button.accessibilityIdentifier = "inboxCategory"
        return button
    }

    /// Shows `selected` on the pill and offers every category, with its unread count.
    static func update(
        _ button: UIButton, selected: InboxCategory, unreadCounts: [InboxCategory: Int],
        select: @escaping (InboxCategory) -> Void
    ) {
        button.configuration?.title = selected.title
        button.accessibilityLabel = String(
            localized: "Inbox category: \(selected.title)", table: "Mailbox", bundle: .module,
            comment: "VoiceOver: the Inbox category menu, with the category shown")
        button.menu = UIMenu(
            children: InboxCategory.allCases.map { category in
                let action = UIAction(title: category.title, image: UIImage(systemName: category.symbol)) { _ in
                    select(category)
                }
                if let unread = unreadCounts[category] {
                    action.subtitle = String(
                        localized: "\(unread) unread", table: "Mailbox", bundle: .module,
                        comment: "Inbox category menu: unread threads in a category")
                }
                action.state = category == selected ? .on : .off
                return action
            })
    }
}
