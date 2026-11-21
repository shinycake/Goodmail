public import Foundation
public import MailCore
public import Observation

/// Every account's sync health, which each sync reports to, and whether its alerts can come, which each
/// registration with the relay reports to. The mailbox lists show from it. One per app, shared by every window.
@Observable
public final class AccountHealthBoard {
    public private(set) var health: [AccountID: AccountHealth] = [:]
    public private(set) var alerts: [AccountID: AlertHealth] = [:]
    /// How many syncs are under way now, across the accounts.
    public private(set) var syncsUnderWay = 0
    /// When a sync of any account last worked.
    public private(set) var lastUpdated: Date?
    @ObservationIgnored private let now: () -> Date

    public init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    /// Tells the board how a sync of `id` ended.
    public func record(_ outcome: Result<Void, any Error>, for id: AccountID) {
        if case .success = outcome { lastUpdated = now() }
        let after = (health[id] ?? .healthy).after(outcome, at: now())
        // Syncs end every 30 seconds; only a change should redraw what shows the board.
        if health[id] != after { health[id] = after }
    }

    /// Tells the board a sync began; each one ends with `syncEnded`.
    public func syncStarted() {
        syncsUnderWay += 1
    }

    public func syncEnded() {
        assert(syncsUnderWay > 0, "a sync ended that never started")
        syncsUnderWay -= 1
    }

    /// Tells the board how registering `id` for alerts with the relay ended.
    public func recordAlerts(_ outcome: Result<Void, any Error>, for id: AccountID) {
        let after = (alerts[id] ?? .working).after(outcome, at: now())
        if alerts[id] != after { alerts[id] = after }
    }

    /// Forgets a removed account.
    public func forget(_ id: AccountID) {
        health[id] = nil
        alerts[id] = nil
    }

    /// The problems of `accounts` the reader should hear of, in their order. An account that can't sync says so
    /// first: its alerts matter once its mail arrives again.
    public func notices(for accounts: [Account]) -> [AccountProblemNotice] {
        accounts.compactMap { account in
            let problem = health[account.id]?.problem ?? (alerts[account.id] == .paused ? .alertsPaused : nil)
            return problem.map { AccountProblemNotice(account: account, problem: $0) }
        }
    }
}

/// One account's problem, as a mailbox list tells it.
nonisolated public struct AccountProblemNotice: Equatable, Sendable {
    public let account: Account
    public let problem: AccountProblem
}
