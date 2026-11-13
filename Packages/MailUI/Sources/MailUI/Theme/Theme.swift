import MailCore
import UIKit

/// The one color a screen wears on its large title, its controls and its primary action: the account's color in a
/// view of one account, or the blend of every account's in a view that spans them.
public enum Theme: Equatable {
    case account(AccountColor)
    case blend(AccountBlend)

    /// The theme of a view of `accountID`'s mail, or of every account's when it is `nil`. Spanning a single account is
    /// that account's view. An account that is gone, as while it is being removed, leaves the system tint.
    public init(accountID: AccountID?, among accounts: [Account]) {
        switch accountID {
        case let id?:
            self = accounts.first { $0.id == id }.map { .account($0.color) } ?? .blend(AccountBlend([]))
        case nil where accounts.count == 1:
            self = .account(accounts[0].color)
        case nil:
            self = .blend(AccountBlend(accounts.map(\.color)))
        }
    }

    public var tint: UIColor {
        switch self {
        case .account(let color): color.uiColor
        case .blend(let blend): blend.tint
        }
    }

    /// What a thread row shows of `account`. A view of one account already says which it is, so its rows mark only
    /// unread mail; a view that spans accounts marks every row with its own account's color.
    func rowAccount(_ account: Account) -> RowAccount {
        switch self {
        case .account: .implied(account.color)
        case .blend: .shown(account.color, email: account.email)
        }
    }
}

/// How a thread row ties itself to its account, on the badge at its avatar's corner.
nonisolated enum RowAccount: Equatable {
    /// The view is the account's own: a dot in its color while the thread is unread, nothing once it is read.
    case implied(AccountColor)
    /// The view spans accounts: a dot in the account's color while unread, a ring once read, and the address for
    /// VoiceOver.
    case shown(AccountColor, email: String)
}

extension UIViewController {
    /// Puts `theme` on this screen and on the navigation bar and toolbar it shares with the rest of its stack. Call
    /// from `viewWillAppear`, so each screen restores its own as the stack moves.
    func wear(_ theme: Theme) {
        let tint = theme.tint
        view.tintColor = tint
        guard let navigationController else { return }
        navigationController.navigationBar.tintColor = tint
        navigationController.toolbar.tintColor = tint
        navigationController.navigationBar.largeTitleTextAttributes = [
            .font: Typography.serif(.largeTitle, weight: .bold), .foregroundColor: tint,
        ]
    }
}
