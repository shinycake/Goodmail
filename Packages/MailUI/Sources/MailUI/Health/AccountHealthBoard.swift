import Foundation
import MailCore
import Observation

/// Every account's sync health, which each sync reports to and the mailbox lists show from. One per app, shared by
/// every window.
@Observable
public final class AccountHealthBoard {
    public private(set) var health: [AccountID: AccountHealth] = [:]
    @ObservationIgnored private let now: () -> Date

    public init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    /// Tells the board how a sync of `id` ended.
    public func record(_ outcome: Result<Void, any Error>, for id: AccountID) {
        let after = (health[id] ?? .healthy).after(outcome, at: now())
        // Syncs end every 30 seconds; only a change should redraw what shows the board.
        if health[id] != after { health[id] = after }
    }

    /// Forgets a removed account.
    public func forget(_ id: AccountID) {
        health[id] = nil
    }

    /// The problems of `accounts` the reader should hear of, in their order.
    public func notices(for accounts: [Account]) -> [AccountProblemNotice] {
        accounts.compactMap { account in
            health[account.id]?.problem.map { AccountProblemNotice(account: account, problem: $0) }
        }
    }
}

/// One account's problem, as a mailbox list tells it.
nonisolated public struct AccountProblemNotice: Equatable, Sendable {
    public let account: Account
    public let problem: AccountProblem
}
