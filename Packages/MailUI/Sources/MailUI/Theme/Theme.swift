public import MailCore
public import UIKit

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

    /// How a large title is set in `font`: in the text color when the theme is a gradient, which shows in the bar
    /// under it (`titleBar(for:font:)`) without coloring the letters; otherwise in the tint.
    func titleAttributes(font: UIFont) -> [NSAttributedString.Key: Any] {
        switch self {
        case .gradient(let blend) where blend.colors.count > 1: [.font: font, .foregroundColor: UIColor.label]
        case .account, .gradient, .solid: [.font: font, .foregroundColor: tint]
        }
    }

    /// The thin gradient bar under `title` set in `font` as a large title, when the theme is a gradient.
    func titleBar(for title: String, font: UIFont) -> GradientTitleBar? {
        switch self {
        case .gradient(let blend) where blend.colors.count > 1:
            GradientTitleBar(blend: blend, title: TitleInk(title, font: font))
        case .account, .gradient, .solid: nil
        }
    }

    /// `symbol` in this theme for `traits`: painted in the gradient, when the theme is one, or in the tint.
    func paint(_ symbol: UIImage, in traits: UITraitCollection, direction: UIUserInterfaceLayoutDirection) -> UIImage {
        switch self {
        case .gradient(let blend) where blend.colors.count > 1:
            blend.paint(symbol, in: traits, direction: direction)
        case .account, .gradient, .solid:
            symbol.withTintColor(tint.resolvedColor(with: traits), renderingMode: .alwaysOriginal)
        }
    }

    /// What a thread row shows of `account`. A view of one account already says which it is, so its rows mark only
    /// unread mail; a view that spans accounts marks every row with its own account's color.
    func rowAccount(_ account: Account) -> RowAccount {
        switch self {
        case .account: .implied(account.color)
        case .gradient, .solid: .shown(account.color, name: account.title)
        }
    }
}

/// How a thread row ties itself to its account, on the badge at its avatar's corner.
nonisolated enum RowAccount: Equatable {
    /// The view is the account's own: a dot in its color while the thread is unread, nothing once it is read.
    case implied(AccountColor)
    /// The view spans accounts: a dot in the account's color while unread, a ring once read, and the account's name
    /// (`Account.title`) for VoiceOver.
    case shown(AccountColor, name: String)
}

extension UIViewController {
    /// Puts `theme` on this screen and on the navigation bar and toolbar it shares with the rest of its stack. Call
    /// from `viewWillAppear`, after the screen has its title: a gradient bar is laid under it, as wide as the title.
    func wear(_ theme: Theme) {
        let tint = theme.tint
        view.tintColor = tint
        guard let navigationController else { return }
        navigationController.navigationBar.tintColor = tint
        navigationController.toolbar.tintColor = tint
        let font = Typography.system(.largeTitle, weight: .bold)
        navigationController.navigationBar.largeTitleTextAttributes = theme.titleAttributes(font: font)
        navigationItem.largeSubtitleView = theme.titleBar(for: navigationItem.title ?? self.title ?? "", font: font)
    }
}
