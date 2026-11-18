public import Foundation
public import MailWrist

extension WristOwnHost {
    /// Whether the watch is checking its own mail now (ADR-023), and when a check of it last worked.
    public enum Checking: Equatable, Sendable {
        case idle(lastChecked: Date?)
        case running(lastChecked: Date?)

        /// When a check last worked for at least one account, if one has.
        public var lastChecked: Date? {
            switch self {
            case .idle(let date), .running(let date): date
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
