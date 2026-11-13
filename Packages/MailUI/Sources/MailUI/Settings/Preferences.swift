import Foundation
import MailCore

/// The reader's choices, kept on this device.
public enum Preferences {
    /// The undo-send waits offered, in seconds; zero sends at once.
    public static let undoSendChoices = [0, 5, 10, 20, 30]

    /// How long a sent message waits before it goes, so it can be taken back.
    public static var undoSendSeconds: Int {
        get { defaults.object(forKey: undoSendKey) as? Int ?? 10 }
        set { defaults.set(newValue, forKey: undoSendKey) }
    }

    /// Accounts whose Inbox isn't split into Gmail's categories: all of their Inbox shows as Primary.
    public static var unsortedInboxAccounts: Set<AccountID> {
        get { Set((defaults.stringArray(forKey: unsortedInboxKey) ?? []).map(AccountID.init(rawValue:))) }
        set { defaults.set(newValue.map(\.rawValue).sorted(), forKey: unsortedInboxKey) }
    }

    /// How mailbox rows look.
    public static var rowDisplay: RowDisplay {
        get {
            RowDisplay(
                previewLines: defaults.object(forKey: previewLinesKey) as? Int ?? RowDisplay.standard.previewLines,
                showsAvatars: defaults.object(forKey: showsAvatarsKey) as? Bool ?? RowDisplay.standard.showsAvatars)
        }
        set {
            defaults.set(newValue.previewLines, forKey: previewLinesKey)
            defaults.set(newValue.showsAvatars, forKey: showsAvatarsKey)
        }
    }

    private static let undoSendKey = "undoSendSeconds"
    private static let previewLinesKey = "previewLines"
    private static let showsAvatarsKey = "showsAvatars"
    private static let unsortedInboxKey = "unsortedInboxAccounts"
    nonisolated(unsafe) private static let defaults = UserDefaults.standard
}
