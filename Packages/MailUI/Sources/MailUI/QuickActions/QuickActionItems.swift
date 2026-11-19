public import MailCore
public import UIKit

extension UIApplicationShortcutItem {
    /// The Home Screen menu for `accounts` and the newest draft, most useful first (`QuickAction.menu`).
    public static func quickActions(accounts: [Account], newestDraft: ThreadSummary?) -> [UIApplicationShortcutItem] {
        QuickAction.menu(accounts: accounts.map(\.id), newestDraft: newestDraft?.id).compactMap { action in
            let account = accounts.first { $0.id == action.accountID }
            return UIApplicationShortcutItem(action, account: account, draft: newestDraft)
        }
    }

    /// The item for `action`, named after its `account` or `draft` where it has one; `nil` if it can't be carried.
    private convenience init?(_ action: QuickAction, account: Account?, draft: ThreadSummary?) {
        guard let data = try? action.encoded() else { return nil }
        let (title, subtitle, symbol) = Self.presentation(of: action, account: account, draft: draft)
        self.init(
            type: action.type, localizedTitle: title, localizedSubtitle: subtitle,
            icon: UIApplicationShortcutIcon(systemImageName: symbol),
            userInfo: [Self.actionKey: data as NSData])
    }

    /// The action the item stands for; `nil` for one this build doesn't read, as after an update.
    public var quickAction: QuickAction? {
        guard let data = userInfo?[Self.actionKey] as? Data else { return nil }
        return try? QuickAction(encoded: data)
    }

    private static let actionKey = "action"

    private static func presentation(
        of action: QuickAction, account: Account?, draft: ThreadSummary?
    ) -> (title: String, subtitle: String?, symbol: String) {
        switch action {
        case .newMessage:
            (
                String(
                    localized: "New Message", table: "QuickActions", bundle: .module,
                    comment: "Home Screen quick action that starts a new email"),
                nil, "square.and.pencil"
            )
        case .search:
            (
                String(
                    localized: "Search", table: "QuickActions", bundle: .module,
                    comment: "Home Screen quick action that opens the search field"),
                nil, "magnifyingglass"
            )
        case .unread:
            (
                String(
                    localized: "Unread", table: "QuickActions", bundle: .module,
                    comment: "Home Screen quick action that lists the unread mail in every account"),
                nil, "envelope.badge"
            )
        case .draft:
            (
                String(
                    localized: "Continue Draft", table: "QuickActions", bundle: .module,
                    comment: "Home Screen quick action that opens the newest draft in the composer, its subject below"),
                draft.map(\.subject).flatMap { $0.isEmpty ? nil : $0 }
                    ?? String(
                        localized: "No Subject", table: "QuickActions", bundle: .module,
                        comment: "Below Continue Draft, for a draft that has no subject"),
                "doc"
            )
        case .inbox:
            (
                account?.title ?? "",
                String(
                    localized: "Inbox", table: "QuickActions", bundle: .module,
                    comment: "Below an account's name, in the Home Screen quick action that opens its Inbox"),
                "tray"
            )
        }
    }
}

extension QuickAction {
    /// The account the action names, if it names one.
    fileprivate var accountID: AccountID? {
        switch self {
        case .newMessage, .search, .unread: nil
        case .draft(let id): id.accountID
        case .inbox(let id): id
        }
    }
}
