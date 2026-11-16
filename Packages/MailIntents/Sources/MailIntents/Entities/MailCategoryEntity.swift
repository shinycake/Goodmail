public import AppIntents
import MailCore

/// The Inbox tab Gmail sorts a message into.
@AppEnum(schema: .mail.category)
public enum MailCategoryEntity: String, AppEnum {
    case primary, promotions, social, updates, forums

    public static let caseDisplayRepresentations: [MailCategoryEntity: DisplayRepresentation] = [
        .primary: DisplayRepresentation(title: LocalizedStringResource("Primary", table: "ShortcutMail")),
        .promotions: DisplayRepresentation(title: LocalizedStringResource("Promotions", table: "ShortcutMail")),
        .social: DisplayRepresentation(title: LocalizedStringResource("Social", table: "ShortcutMail")),
        .updates: DisplayRepresentation(title: LocalizedStringResource("Updates", table: "ShortcutMail")),
        .forums: DisplayRepresentation(title: LocalizedStringResource("Forums", table: "ShortcutMail")),
    ]

    /// The category a message carrying `labels` is in, or `nil` when it isn't in the Inbox.
    init?(labels: Set<String>) {
        guard labels.contains(SystemLabel.inbox) else { return nil }
        let category = InboxCategory.allCases.first { labels.contains($0.labelID) } ?? .primary
        self.init(rawValue: category.rawValue)
    }
}
