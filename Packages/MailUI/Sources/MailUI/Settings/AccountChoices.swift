import Foundation
public import MailCore
public import Observation

/// One choice per account that Settings shows and the app keeps, as each account's alerts (`NotificationChoices`) or
/// what it counts toward the badge (`BadgeChoices`), with whether the reader turned the feature off in iOS Settings,
/// where only they can turn it back on.
///
/// Reads and stores run one after another (`TaskChain`), so a read made as the screen appears again never shows
/// the value from before a choice whose store hadn't finished.
@Observable
public final class AccountChoices<Choice: Hashable & Sendable> {
    public enum Status {
        /// Not read yet: no account shows a choice, and nothing says the feature is off.
        case loading
        /// `choices` are each account's; `turnedOff` is whether iOS Settings turned the feature off.
        case loaded(choices: [AccountID: Choice], turnedOff: Bool)
    }

    public private(set) var status = Status.loading

    @ObservationIgnored private let read: () async -> [AccountID: Choice]
    @ObservationIgnored private let store: (Choice, AccountID) async -> Void
    @ObservationIgnored private let turnedOff: () async -> Bool
    @ObservationIgnored private let changes = TaskChain()

    /// `read` loads every account's choice; `store` keeps one; `turnedOff` asks iOS whether the reader turned the
    /// feature off.
    public init(
        read: @escaping () async -> [AccountID: Choice],
        store: @escaping (Choice, AccountID) async -> Void,
        turnedOff: @escaping () async -> Bool
    ) {
        self.read = read
        self.store = store
        self.turnedOff = turnedOff
    }

    /// The account's choice, once read.
    func choice(for account: AccountID) -> Choice? {
        if case .loaded(let choices, _) = status { choices[account] } else { nil }
    }

    /// Whether the reader turned the feature off in iOS Settings; `false` until that is known.
    var isTurnedOffInSettings: Bool {
        if case .loaded(_, let turnedOff) = status { turnedOff } else { false }
    }

    /// Reads the choices and asks iOS again, after any choice made before is stored.
    func load() async {
        // A choice made from here on is stored after this read, which can't see it, so the read keeps it as shown.
        let before = shown
        changes.run { [self] in
            let turnedOff = await turnedOff()
            var choices = await read()
            for (account, choice) in shown where before[account] != choice { choices[account] = choice }
            status = .loaded(choices: choices, turnedOff: turnedOff)
        }
        await changes.settled()
    }

    /// Shows the choice at once and stores it after what was asked for before it. Nothing before the choices are read.
    func set(_ choice: Choice, for account: AccountID) {
        guard case .loaded(var choices, let turnedOff) = status else { return }
        choices[account] = choice
        status = .loaded(choices: choices, turnedOff: turnedOff)
        changes.run { [self] in await store(choice, account) }
    }

    /// Waits until everything asked for so far has run, as a test does.
    func settled() async {
        await changes.settled()
    }

    private var shown: [AccountID: Choice] {
        if case .loaded(let choices, _) = status { choices } else { [:] }
    }
}
