public import Foundation
public import MailCore

extension WristMailbox {
    /// How long the iPhone can stay quiet before the rows it serves say they need it.
    public static let phoneQuietLimit: TimeInterval = 30 * 60

    /// Whether the rows of `account` say "Needs iPhone" at `now`: the iPhone serves it and hasn't sent mail for
    /// `phoneQuietLimit`, while the watch reads other accounts itself, whose rows stay current (ADR-023). A watch that
    /// reads nothing itself shows the iPhone's mail as before, without the mark.
    public func needsIPhone(_ account: AccountID, now: Date) -> Bool {
        guard let snapshot, sources.values.contains(.direct), sources[account] != .direct else { return false }
        return now.timeIntervalSince(snapshot.madeAt) > Self.phoneQuietLimit
    }
}
