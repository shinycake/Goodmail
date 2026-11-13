import AppIntents
import MailCore

/// The Inbox tab Gmail sorts a message into.
@AppEnum(schema: .mail.category)
public enum MailCategoryEntity: String, AppEnum {
    case primary, promotions, social, updates, forums

    public static let caseDisplayRepresentations: [MailCategoryEntity: DisplayRepresentation] = [
        .primary: "Primary",
        .promotions: "Promotions",
        .social: "Social",
        .updates: "Updates",
        .forums: "Forums",
    ]

    /// The category a message carrying `labels` is in, or `nil` when it isn't in the Inbox.
    init?(labels: Set<String>) {
        guard labels.contains(SystemLabel.inbox) else { return nil }
        let category = InboxCategory.allCases.first { labels.contains($0.labelID) } ?? .primary
        self.init(rawValue: category.rawValue)
    }
}
