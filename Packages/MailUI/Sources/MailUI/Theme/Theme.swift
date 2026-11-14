import MailCore
import UIKit

/// What a screen wears on its large title, its controls and its primary action: the account's color in a view of one
/// account, and in a view that spans them a gradient through every account's color, or the one color the reader
/// chose instead (`CombinedTheme`).
public enum Theme: Equatable {
    case account(AccountColor)
    /// A view spanning accounts, in a gradient through their colors.
    case gradient(AccountBlend)
    /// A view spanning accounts, in the one color the reader chose.
    case solid(AccountColor)

    /// The theme of a view of `accountID`'s mail, or of every account's when it is `nil`, which wears `combined`.
    /// Spanning a single account is that account's view. An account that is gone, as while it is being removed,
    /// leaves the system tint.
    public init(accountID: AccountID?, among accounts: [Account], combined: CombinedTheme) {
        switch (accountID, combined) {
        case (let id?, _):
            self = accounts.first { $0.id == id }.map { .account($0.color) } ?? .gradient(AccountBlend([]))
        case (nil, _) where accounts.count == 1:
            self = .account(accounts[0].color)
        case (nil, .gradient):
            self = .gradient(AccountBlend(accounts.map(\.color)))
        case (nil, .solid(let color)):
            self = .solid(color)
        }
    }

    /// The one color of controls, which can't wear a gradient.
    public var tint: UIColor {
        switch self {
        case .account(let color), .solid(let color): color.uiColor
        case .gradient(let blend): blend.tint
        }
    }

    /// The color of `title` set in `font`: the gradient, when the theme is one, or the tint.
    func titleColor(for title: String, font: UIFont, direction: UIUserInterfaceLayoutDirection) -> UIColor {
        switch self {
        case .gradient(let blend) where blend.colors.count > 1:
            blend.textColor(width: (title as NSString).size(withAttributes: [.font: font]).width, direction: direction)
        case .account, .gradient, .solid:
            tint
        }
    }

    /// What a thread row shows of `account`. A view of one account already says which it is, so its rows mark only
    /// unread mail; a view that spans accounts marks every row with its own account's color.
    func rowAccount(_ account: Account) -> RowAccount {
        switch self {
        case .account: .implied(account.color)
        case .gradient, .solid: .shown(account.color, email: account.email)
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
    /// from `viewWillAppear`, after the screen has its title: a gradient is laid across the title's width.
    func wear(_ theme: Theme) {
        let tint = theme.tint
        view.tintColor = tint
        guard let navigationController else { return }
        navigationController.navigationBar.tintColor = tint
        navigationController.toolbar.tintColor = tint
        let font = Typography.serif(.largeTitle, weight: .bold)
        let title = theme.titleColor(
            for: navigationItem.title ?? self.title ?? "", font: font,
            direction: view.effectiveUserInterfaceLayoutDirection)
        navigationController.navigationBar.largeTitleTextAttributes = [.font: font, .foregroundColor: title]
    }
}
