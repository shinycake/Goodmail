public import Foundation
import MailCore

/// What the watch shows: the iPhone's last snapshot with the reader's changes the iPhone hasn't confirmed yet laid
/// over it, so a swipe takes effect at once and stays in effect over an older snapshot until the iPhone has run it.
public struct WristMailbox: Codable, Equatable, Sendable {
    /// A change the iPhone hasn't confirmed in this long is dropped: it was lost, or the iPhone couldn't run it.
    static let pendingLifetime: TimeInterval = 24 * 60 * 60

    public private(set) var snapshot: WristSnapshot?
    /// Oldest first.
    public private(set) var pending: [WristCommand] = []

    public init(snapshot: WristSnapshot? = nil, pending: [WristCommand] = []) {
        self.snapshot = snapshot
        self.pending = pending
    }

    /// Takes the iPhone's newest snapshot, and lets go of the changes it confirms and those too old to wait for.
    public mutating func receive(_ snapshot: WristSnapshot, now: Date) {
        self.snapshot = snapshot
        let applied = Set(snapshot.applied)
        pending.removeAll { applied.contains($0.id) || now.timeIntervalSince($0.madeAt) > Self.pendingLifetime }
    }

    public mutating func perform(_ command: WristCommand) {
        pending.append(command)
    }

    /// Takes back `command`. Its effect goes at once; the returned inverse is for the iPhone, which may have run it
    /// already.
    public mutating func undo(_ command: WristCommand, now: Date) -> WristCommand {
        pending.removeAll { $0.id == command.id }
        let inverse = command.inverse(madeAt: now)
        pending.append(inverse)
        return inverse
    }

    /// The snapshot as the reader expects it after their changes.
    public var shown: WristSnapshot? {
        snapshot.map { pending.reduce($0) { $0.applying($1) } }
    }
}

extension WristSnapshot {
    /// The snapshot with `command`'s effect on the rows and unread counts. Moving a thread back into the Inbox has no
    /// effect here: the watch doesn't have the row, so it shows up with the iPhone's next snapshot.
    func applying(_ command: WristCommand) -> WristSnapshot {
        let threads = Set(command.threads)
        var result = self
        switch command.kind {
        case .archive, .trash:
            result.rows.removeAll { threads.contains($0.id) }
        case .moveToInbox, .untrash:
            return self
        case .markRead(let read):
            result.rows = rows.map { row in
                guard threads.contains(row.id) else { return row }
                var row = row
                row.isUnread = !read
                return row
            }
        case .pin(let pinned):
            let changed = rows.map { row in
                guard threads.contains(row.id) else { return row }
                var row = row
                row.isPinned = pinned
                return row
            }
            let newestFirst = changed.sorted { $0.date > $1.date }
            result.rows = newestFirst.filter(\.isPinned) + newestFirst.filter { !$0.isPinned }
        }
        result.recountUnread(from: self)
        return result
    }

    /// Moves each account's unread count by how many of its rows stopped or started being unread since `before`.
    private mutating func recountUnread(from before: WristSnapshot) {
        func unread(_ rows: [WristRow]) -> [AccountID: Int] {
            rows.filter(\.isUnread).reduce(into: [:]) { $0[$1.id.accountID, default: 0] += 1 }
        }
        let was = unread(before.rows)
        let now = unread(rows)
        accounts = accounts.map { account in
            var account = account
            account.unread = max(0, account.unread + (now[account.id] ?? 0) - (was[account.id] ?? 0))
            return account
        }
    }
}
