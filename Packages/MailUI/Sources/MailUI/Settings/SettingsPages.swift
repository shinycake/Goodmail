public import MailCore
public import Observation
import SwiftUI

/// The screens pushed over Settings' first one: seeded from the page Settings opens at, then the reader's, and the
/// Settings window's to add to when a page is asked for while it is open.
@Observable
public final class SettingsPages {
    /// Untyped, because the screens push more than pages: an account row pushes its `AccountID`, and a path typed to
    /// `SettingsPage` silently drops that push.
    var path: NavigationPath

    public init(at page: SettingsPage = .main) {
        path = Self.path(to: page)
    }

    /// Shows `page` over the first screen, in place of whatever the reader had moved on to. The first screen itself
    /// leaves the reader where they are, as asking for Settings again brings it forward as it was.
    public func show(_ page: SettingsPage) {
        guard page != .main else { return }
        path = Self.path(to: page)
    }

    private static func path(to page: SettingsPage) -> NavigationPath {
        switch page {
        case .main: NavigationPath()
        case .swipeActions: NavigationPath([page])
        }
    }
}
