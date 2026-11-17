public import Foundation
public import MailCore

/// What the watch's list footer says about the mail it reads itself (ADR-023): when it last checked, that it is
/// checking now, or why it can't. Relayed accounts say "Needs iPhone" on their own rows instead.
public enum WristFreshness: Equatable, Sendable {
    /// The last check worked, at `checkedAt`.
    case current(checkedAt: Date)
    /// A check is running; `lastChecked` is when one last worked, if one has.
    case checking(lastChecked: Date?)
    /// Checks have failed long enough to say so (`AccountHealth.patience`), the latest for `reason`.
    case behind(FailureReason, lastChecked: Date?)

    /// The footer for the watch's own accounts: `checking` while a check runs, `lastChecked` when the last one worked,
    /// and their `health`. The worst account speaks for all of them, since one footer covers the list.
    public init(checking: Bool, lastChecked: Date?, health: [AccountHealth]) {
        if let reason = health.lazy.compactMap(\.reportedReason).first {
            self = .behind(reason, lastChecked: lastChecked)
        } else if !checking, let lastChecked {
            self = .current(checkedAt: lastChecked)
        } else {
            // Before the first check has worked, the watch is about to make one.
            self = .checking(lastChecked: lastChecked)
        }
    }
}

extension AccountHealth {
    /// Why checks fail, once they have for long enough to tell the reader.
    fileprivate var reportedReason: FailureReason? {
        switch self {
        case .healthy, .faltering: nil
        case .failing(let reason): reason
        case .needsSignIn: .signInFailed
        }
    }
}
