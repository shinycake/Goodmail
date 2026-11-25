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

    }

    /// Whether checks run now, and when one last worked, in the stretch the switch is on: idle and never checked
    /// while it is off.
    public var checking: Checking {
        guard let stretch = independence.stretch else { return .idle(lastChecked: nil) }
        if stretch.checks.isEmpty { return .idle(lastChecked: stretch.lastChecked) }
        return .running(runs: stretch.checks.count, lastChecked: stretch.lastChecked)
    }

    /// What the list footer says about the mail the watch reads itself, or `nil` while it reads none, as while the
    /// switch is off.
    public func freshness() -> WristFreshness? {
        let served = independence.served
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
