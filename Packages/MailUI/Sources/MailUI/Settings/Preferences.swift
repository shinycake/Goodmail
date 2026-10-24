import Foundation

/// The reader's choices, kept on this device.
public enum Preferences {
    /// The undo-send waits offered, in seconds; zero sends at once.
    public static let undoSendChoices = [0, 5, 10, 20, 30]

    /// How long a sent message waits before it goes, so it can be taken back.
    public static var undoSendSeconds: Int {
        get { defaults.object(forKey: undoSendKey) as? Int ?? 10 }
        set { defaults.set(newValue, forKey: undoSendKey) }
    }

    private static let undoSendKey = "undoSendSeconds"
    nonisolated(unsafe) private static let defaults = UserDefaults.standard
}
