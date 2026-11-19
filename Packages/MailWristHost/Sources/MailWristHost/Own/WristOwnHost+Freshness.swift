public import Foundation
public import MailWrist

extension WristOwnHost {
    /// Whether the watch is checking its own mail now (ADR-023), and when a check of it last worked.
    public enum Checking: Equatable, Sendable {
        case idle(lastChecked: Date?)
        /// `runs` checks at once, one or more, as a check at launch beside a background catch-up.
        case running(runs: Int, lastChecked: Date?)

        /// When a check last worked for at least one account, if one has.
        public var lastChecked: Date? {
            switch self {
            case .idle(let date), .running(_, let date): date
            }
        }

        /// A check starts, beside any already running.
        mutating func start() {
            switch self {
            case .idle(let date): self = .running(runs: 1, lastChecked: date)
            case .running(let runs, let date): self = .running(runs: runs + 1, lastChecked: date)
            }
        }

        /// A check ended, having worked for at least one account at `date`, or with `nil` when it didn't or was cut
        /// short. A later date is never replaced by an earlier one.
        mutating func end(workedAt date: Date?) {
            let latest = [lastChecked, date].compactMap(\.self).max()
            switch self {
            case .running(let runs, _) where runs > 1: self = .running(runs: runs - 1, lastChecked: latest)
            case .idle, .running: self = .idle(lastChecked: latest)
            }
        }
    }

    /// What the list footer says about the mail the watch reads itself, or `nil` while it reads none.
    public func freshness() -> WristFreshness? {
        guard !served.isEmpty else { return nil }
        let running = if case .running = checking { true } else { false }
        return WristFreshness(
            checking: running, lastChecked: checking.lastChecked, health: served.keys.compactMap { health[$0] })
    }

    /// Sends the footer on `freshnessUpdates` when it changed.
    func publishFreshness() {
        let freshness = freshness()
        guard freshness != published else { return }
        published = freshness
        freshnessContinuation.yield(freshness)
    }
}
