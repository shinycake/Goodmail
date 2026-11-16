public import UserNotifications

/// What a push shows when it brought no new inbox mail to alert for: a read, an archive, a delete, a label change,
/// mail already alerted for, or a fetch that failed or ran out of time.
///
/// iOS shows something for every alert push unless the extension has Apple's notification filtering entitlement.
/// With it, an empty alert shows nothing. Without it, the best left is the push's own "New mail", quiet.
public enum NewMailSilence: Sendable, Equatable {
    /// The extension has the filtering entitlement, so nothing shows.
    case filtered
    /// It doesn't: the push's own text, delivered without a sound or lighting the screen, and stacked apart from
    /// real alerts.
    case quiet

    /// The Info.plist key that says the extension was signed with the filtering entitlement. It's set beside the
    /// entitlement, since an empty alert without the entitlement shows the push as it came, sound and all.
    public static let infoKey = "GoodmailFiltersAlerts"

    /// The silence the extension whose Info.plist is `info` can give.
    public init(info: [String: Any]?) {
        self = info?[Self.infoKey] as? Bool == true ? .filtered : .quiet
    }

    /// What to hand iOS in place of `push`.
    public func content(for push: UNNotificationContent) -> UNNotificationContent {
        switch self {
        case .filtered: return UNNotificationContent()
        case .quiet:
            guard let quiet = push.mutableCopy() as? UNMutableNotificationContent else { return push }
            quiet.sound = nil
            quiet.interruptionLevel = .passive
            quiet.relevanceScore = 0
            quiet.threadIdentifier = NewMailAlert.placeholderThread
            return quiet
        }
    }
}
