import Foundation
public import MailCore

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
                // A stored length outside the choices, as from an older build, reads as the standard one.
                previewLines: (defaults.object(forKey: previewLinesKey) as? Int)
                    .flatMap { RowDisplay.previewLineChoices.contains($0) ? $0 : nil }
                    ?? RowDisplay.standard.previewLines,
                showsAvatars: defaults.object(forKey: showsAvatarsKey) as? Bool ?? RowDisplay.standard.showsAvatars)
        }
        set {
            defaults.set(newValue.previewLines, forKey: previewLinesKey)
            defaults.set(newValue.showsAvatars, forKey: showsAvatarsKey)
        }
    }

    /// How conversations open. A stored value from a later build reads as the classic layout.
    public static var conversationLayout: ConversationLayout {
        get { defaults.string(forKey: conversationLayoutKey).flatMap(ConversationLayout.init(rawValue:)) ?? .classic }
        set { defaults.set(newValue.rawValue, forKey: conversationLayoutKey) }
    }

    private static let conversationLayoutKey = "conversationLayout"

    /// How trashed, archived and deleted threads leave the list. A stored value from a later build reads as playful.
    public static var removalAnimation: RemovalAnimation {
        get { defaults.string(forKey: removalAnimationKey).flatMap(RemovalAnimation.init(rawValue:)) ?? .playful }
        set { defaults.set(newValue.rawValue, forKey: removalAnimationKey) }
    }

    private static let removalAnimationKey = "removalAnimation"

    /// What views that span accounts wear. A stored color that no longer exists reads as the gradient.
    public static var combinedTheme: CombinedTheme {
        get {
            defaults.string(forKey: combinedThemeColorKey).flatMap(AccountColor.init(rawValue:)).map(
                CombinedTheme.solid)
                ?? .gradient
        }
        set {
            switch newValue {
            case .gradient: defaults.removeObject(forKey: combinedThemeColorKey)
            case .solid(let color): defaults.set(color.rawValue, forKey: combinedThemeColorKey)
            }
        }
    }

    /// Which actions sit on each side of a mailbox row. A side never set reads as the standard one; one the reader
    /// emptied stays empty.
    public static var swipeArrangement: SwipeArrangement {
        get {
            func side(_ key: String, standard: [SwipeChoice]) -> [SwipeChoice] {
                // A choice this build doesn't know, as from a newer one, is skipped.
                (defaults.stringArray(forKey: key)?.compactMap(SwipeChoice.init(rawValue:))) ?? standard
            }
            return SwipeArrangement(
                leading: side(swipeLeadingKey, standard: SwipeArrangement.standard.leading),
                trailing: side(swipeTrailingKey, standard: SwipeArrangement.standard.trailing))
        }
        set {
            defaults.set(newValue.leading.map(\.rawValue), forKey: swipeLeadingKey)
            defaults.set(newValue.trailing.map(\.rawValue), forKey: swipeTrailingKey)
        }
    }

    /// The tint of each swipe action. One never changed, or stored by a newer build, wears its standard tint.
    public static var swipeTints: SwipeTints {
        get { SwipeTints(stored: defaults.dictionary(forKey: swipeTintsKey) as? [String: String] ?? [:]) }
        set { defaults.set(newValue.stored, forKey: swipeTintsKey) }
    }

    /// Accounts from the reader's other devices that this device doesn't take on its own: ones the reader left out
    /// of an offer, or removed from this device only. Settings still lists them, to add by hand.
    public static var declinedSharedAccounts: Set<AccountID> {
        get { Set((defaults.stringArray(forKey: declinedSharedKey) ?? []).map(AccountID.init(rawValue:))) }
        set { defaults.set(newValue.map(\.rawValue).sorted(), forKey: declinedSharedKey) }
    }

    private static let declinedSharedKey = "declinedSharedAccounts"
    private static let swipeTintsKey = "swipeTints"
    private static let undoSendKey = "undoSendSeconds"
    private static let swipeLeadingKey = "swipeLeadingActions"
    private static let swipeTrailingKey = "swipeTrailingActions"
    private static let previewLinesKey = "previewLines"
    private static let showsAvatarsKey = "showsAvatars"
    private static let unsortedInboxKey = "unsortedInboxAccounts"
    private static let combinedThemeColorKey = "combinedThemeColor"
    private static let defaults = UserDefaults.standard
}
