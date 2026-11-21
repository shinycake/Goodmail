import Foundation
public import MailCore

/// The choices of a Mac's windows. They belong to this Mac alone: they aren't in `Preferences.syncedSettings`
/// (ADR-024), since an iPhone has no Delete key or double-click to answer for.
public enum DesktopPreferences {
    /// What the Delete key does to the picked conversations. A stored name from a later build reads as Trash.
    public static var deleteKey: DeleteKeyAction {
        get { defaults.string(forKey: deleteKeyKey).flatMap(DeleteKeyAction.init(rawValue:)) ?? .standard }
        set { defaults.set(newValue.rawValue, forKey: deleteKeyKey) }
    }

    /// Whether a double-click on a conversation opens it in a window of its own, as in Apple Mail. Return does either
    /// way.
    public static var doubleClickOpensWindow: Bool {
        get { defaults.object(forKey: doubleClickKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: doubleClickKey) }
    }

    private static let defaults = UserDefaults.standard
    private static let deleteKeyKey = "desktopDeleteKey"
    private static let doubleClickKey = "desktopDoubleClickOpensWindow"
}
