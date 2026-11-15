import Foundation

/// Which of an account's unread mail counts toward the number on the app's icon, as Mail's Badge App Icon setting.
/// It is separate from the account's alert choice: a reader can silence an account and still see what waits there.
public enum BadgeSource: String, CaseIterable, Codable, Sendable {
    /// Every unread thread in the Inbox.
    case inbox
    /// Only unread threads the service sorts as Primary. Offered for services with Inbox categories.
    case primary
    /// The account adds nothing to the badge.
    case off

    /// What an account counts until the reader chooses.
    public static let initial = BadgeSource.inbox

    /// The choices an account offers: Primary only where the service sorts its Inbox.
    public static func choices(for service: MailService) -> [BadgeSource] {
        service.hasInboxCategories ? [.inbox, .primary, .off] : [.inbox, .off]
    }
}
