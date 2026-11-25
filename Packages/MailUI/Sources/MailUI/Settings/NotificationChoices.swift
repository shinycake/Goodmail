import Foundation
public import MailCore

/// Each account's alert choice, and whether iOS lets the app alert at all.
public typealias NotificationChoices = AccountChoices<NotificationLevel>

extension AccountChoices where Choice == NotificationLevel {
    /// The choices an account offers: Primary only where the service sorts its Inbox.
    static func levels(for service: MailService) -> [NotificationLevel] {
        service.hasInboxCategories ? [.all, .primary, .off] : [.all, .off]
    }

    static func title(_ level: NotificationLevel) -> String {
        switch level {
        case .all:
            String(
                localized: "All New Mail", table: "Settings", bundle: .module,
                comment: "Alert choice: every new Inbox message")
        case .primary:
            String(
                localized: "Primary Only", table: "Settings", bundle: .module,
                comment: "Alert choice: only Primary-category mail")
        case .off:
            String(
                localized: "None", table: "Settings", bundle: .module,
                comment: "Alert choice: no alerts for this account")
        }
    }
}
