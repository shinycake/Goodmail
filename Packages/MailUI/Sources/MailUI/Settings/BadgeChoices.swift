import Foundation
public import MailCore

/// What each account counts toward the app's badge, and whether iOS shows the badge at all.
public typealias BadgeChoices = AccountChoices<BadgeSource>

extension AccountChoices where Choice == BadgeSource {
    /// The choices an account offers. Primary Only needs the Inbox sorted into categories, unless it is already the
    /// choice, so the picker still shows what is stored.
    static func choices(for account: Account, sorted: Bool, current: BadgeSource) -> [BadgeSource] {
        BadgeSource.choices(for: account.service).filter { $0 != .primary || sorted || current == .primary }
    }

    static func title(_ source: BadgeSource) -> String {
        switch source {
        case .inbox:
            String(
                localized: "Unread in Inbox", table: "Badge", bundle: .module,
                comment: "Badge choice: every unread Inbox thread counts")
        case .primary:
            String(
                localized: "Unread in Primary", table: "Badge", bundle: .module,
                comment: "Badge choice: only unread Primary-category threads count")
        case .off:
            String(
                localized: "None", table: "Badge", bundle: .module,
                comment: "Badge choice: the account adds nothing to the badge")
        }
    }
}
