import UIKit

extension UIBackgroundConfiguration {
    /// This background kept to the part of `cell` on show. Side by side on iPad, the sidebar floats over the list's
    /// leading edge and the list runs on under its glass, so a row's tint drawn the cell's full width would show through
    /// the sidebar as a band.
    func kept(toSafeAreaOf cell: UIView) -> UIBackgroundConfiguration {
        var kept = self
        let insets = cell.safeAreaInsets
        let rightToLeft = cell.effectiveUserInterfaceLayoutDirection == .rightToLeft
        kept.backgroundInsets.leading += rightToLeft ? insets.right : insets.left
        kept.backgroundInsets.trailing += rightToLeft ? insets.left : insets.right
        return kept
    }

    /// The background of a list's section header that stays pinned to the top as the list scrolls: solid, so the rows
    /// scrolling under it don't show through its title.
    static func pinnedHeader(in cell: UIView) -> UIBackgroundConfiguration {
        var background = UIBackgroundConfiguration.listHeader()
        background.backgroundColor = .systemBackground
        return background.kept(toSafeAreaOf: cell)
    }
}
