import Foundation
public import MailCore
public import Observation

/// The Settings rows only a Mac has: Open at Login, what a double-click opens and what Delete does.
@Observable
public final class DesktopSettings {
    /// Whether the Mac opens Goodmail at login, as the system reports it.
    public private(set) var openAtLogin: OpenAtLogin
    /// What the Delete key does to the picked conversations.
    public var deleteKey: DeleteKeyAction {
        didSet { DesktopPreferences.deleteKey = deleteKey }
    }
    /// Whether a double-click opens a conversation in its own window.
    public var doubleClickOpensWindow: Bool {
        didSet { DesktopPreferences.doubleClickOpensWindow = doubleClickOpensWindow }
    }

    @ObservationIgnored private let loginItem: any LoginItemService

    init(loginItem: any LoginItemService) {
        self.loginItem = loginItem
        openAtLogin = OpenAtLogin(loginItem.status)
        deleteKey = DesktopPreferences.deleteKey
        doubleClickOpensWindow = DesktopPreferences.doubleClickOpensWindow
    }

    /// This Mac's settings, or `nil` on a device with no login items, which is everything but a Mac app.
    public static func forThisDevice() -> DesktopSettings? {
        #if targetEnvironment(macCatalyst)
            DesktopSettings(loginItem: SystemLoginItem())
        #else
            nil
        #endif
    }

    /// Reads the login item again, since the reader can change it in System Settings while Goodmail is open.
    public func refresh() {
        openAtLogin = OpenAtLogin(loginItem.status)
    }

    /// Registers or removes the login item to match the toggle, then shows what the system made of it.
    public func setOpensAtLogin(_ on: Bool) {
        guard let change = openAtLogin.change(toggling: on) else { return }
        do {
            switch change {
            case .register: try loginItem.register()
            case .unregister: try loginItem.unregister()
            }
            refresh()
        } catch {
            openAtLogin = .failed(message: error.localizedDescription)
        }
    }

    public func openLoginItemsSettings() {
        loginItem.openSettings()
    }
}
