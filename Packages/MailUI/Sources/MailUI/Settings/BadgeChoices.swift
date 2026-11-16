import Foundation
public import MailCore
public import Observation

/// What each account counts toward the app's badge, and whether iOS shows the badge at all.
@Observable
public final class BadgeChoices {
    /// Filled once the screen opens; an account not here yet shows no choice.
    public private(set) var sources: [AccountID: BadgeSource] = [:]
    /// Whether the reader turned the app's badge off in iOS Settings, where only they can turn it back on.
    public private(set) var isTurnedOffInSettings = false

    @ObservationIgnored private let read: () async -> [AccountID: BadgeSource]
    @ObservationIgnored private let store: (BadgeSource, AccountID) async -> Void
    @ObservationIgnored private let turnedOff: () async -> Bool

    /// `read` loads every account's choice; `store` keeps one; `turnedOff` asks iOS whether the reader denied
    /// alerts or switched off badges.
    public init(
        read: @escaping () async -> [AccountID: BadgeSource],
        store: @escaping (BadgeSource, AccountID) async -> Void,
        turnedOff: @escaping () async -> Bool
    ) {
        self.read = read
        self.store = store
        self.turnedOff = turnedOff
    }

    func load() async {
        isTurnedOffInSettings = await turnedOff()
        sources = await read()
    }

    func set(_ source: BadgeSource, for account: AccountID) async {
        sources[account] = source
        await store(source, account)
    }

    /// The choices an account offers. Primary Only needs the Inbox sorted into categories, unless it is already the
    /// choice, so the picker still shows what is stored.
    static func choices(for account: Account, sorted: Bool, current: BadgeSource) -> [BadgeSource] {
        BadgeSource.choices(for: account.service).filter { $0 != .primary || sorted || current == .primary }
    }

    static func title(_ source: BadgeSource) -> String {
        switch source {
        case .inbox:
            String(
                localized: "Unread in Inbox", table: "Badge", bundle: .module,
                comment: "Badge choice: every unread Inbox thread counts")
        case .primary:
            String(
                localized: "Unread in Primary", table: "Badge", bundle: .module,
                comment: "Badge choice: only unread Primary-category threads count")
        case .off:
            String(
                localized: "None", table: "Badge", bundle: .module,
                comment: "Badge choice: the account adds nothing to the badge")
        }
    }
}
