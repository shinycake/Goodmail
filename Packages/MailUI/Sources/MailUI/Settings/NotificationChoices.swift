import MailCore
import Observation

/// Each account's alert choice, and whether iOS lets the app alert at all.
@Observable
public final class NotificationChoices {
    /// Filled once the screen opens; an account not here yet shows no choice.
    public private(set) var levels: [AccountID: NotificationLevel] = [:]
    /// Whether the reader turned the app's alerts off in iOS Settings, where only they can turn them back on.
    public private(set) var isTurnedOffInSettings = false

    @ObservationIgnored private let read: () async -> [AccountID: NotificationLevel]
    @ObservationIgnored private let store: (NotificationLevel, AccountID) async -> Void
    @ObservationIgnored private let turnedOff: () async -> Bool

    /// `read` loads every account's choice; `store` keeps one and updates its push subscription; `turnedOff`
    /// asks iOS whether the reader denied alerts.
    public init(
        read: @escaping () async -> [AccountID: NotificationLevel],
        store: @escaping (NotificationLevel, AccountID) async -> Void,
        turnedOff: @escaping () async -> Bool
    ) {
        self.read = read
        self.store = store
        self.turnedOff = turnedOff
    }

    func load() async {
        isTurnedOffInSettings = await turnedOff()
        levels = await read()
    }

    func set(_ level: NotificationLevel, for account: AccountID) async {
        levels[account] = level
        await store(level, account)
    }

    /// The choices an account offers: Primary only where the service sorts its Inbox.
    static func levels(for service: MailService) -> [NotificationLevel] {
        service.hasInboxCategories ? [.all, .primary, .off] : [.all, .off]
    }

    static func title(_ level: NotificationLevel) -> String {
        switch level {
        case .all:
            String(
                localized: "All New Mail", table: "Settings", bundle: .module,
                comment: "Alert choice: every new Inbox message")
        case .primary:
            String(
                localized: "Primary Only", table: "Settings", bundle: .module,
                comment: "Alert choice: only Primary-category mail")
        case .off:
            String(
                localized: "None", table: "Settings", bundle: .module,
                comment: "Alert choice: no alerts for this account")
        }
    }
}
