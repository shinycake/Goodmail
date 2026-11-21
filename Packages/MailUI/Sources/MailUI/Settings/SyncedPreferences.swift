public import MailCore

/// The reader's choices kept in `UserDefaults` that follow them to their other devices through `SettingsSync`.
/// Left out on purpose: which shared accounts this device turned down and how it takes part in sharing accounts
/// (each device answers those for itself), Mail Without iPhone (`WatchChoices`, a choice for this iPhone's own watch),
/// recent searches, which are this device's history rather than a choice, and the storage choices
/// (`StoragePreferences`), which suit the room this device has, and a Mac's own choices (`DesktopPreferences`).
extension Preferences {
    /// The name the preferences that shape the mail screens are shared under.
    nonisolated public static let syncedGroup = "preferences"

    nonisolated public static var syncedSettings: [any SettingsFamily] {
        [
            DefaultsValues(
                name: syncedGroup,
                keys: [
                    undoSendKey, unsortedInboxKey, previewLinesKey, showsAvatarsKey, conversationLayoutKey,
                    removalAnimationKey, combinedThemeColorKey, swipeLeftKey, swipeRightKey, swipeTintsKey,
                    showsDoodlesKey, afterRemovalKey,
                ]),
            DefaultsList(name: "imageTrustRules", key: ImageTrustRules.standardKey, storage: .json),
            DefaultsList(name: "unsubscribedLists", key: UnsubscribedLists.standardKey, storage: .strings),
        ]
    }
}
