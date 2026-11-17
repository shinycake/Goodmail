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
    /// Replies the iPhone couldn't send, oldest first, until the reader sends them again or lets them go.
    public private(set) var undelivered: [WristCommand] = []

    public init(snapshot: WristSnapshot? = nil, pending: [WristCommand] = [], undelivered: [WristCommand] = []) {
        self.snapshot = snapshot
        self.pending = pending
        self.undelivered = undelivered
    }

    /// A mailbox stored before `undelivered` existed has none.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            snapshot: try container.decodeIfPresent(WristSnapshot.self, forKey: .snapshot),
            pending: try container.decode([WristCommand].self, forKey: .pending),
            undelivered: try container.decodeIfPresent([WristCommand].self, forKey: .undelivered) ?? [])
    }

    /// Takes the iPhone's newest snapshot, and lets go of the changes it confirms and those too old to wait for. A
    /// reply the iPhone ran and failed to send moves to `undelivered`; other failed changes just go, and the rows show
    /// the mail as it is.
    public mutating func receive(_ snapshot: WristSnapshot, now: Date) {
        self.snapshot = snapshot
        let failed = Set(snapshot.failed)
        undelivered += pending.filter { command in
            guard failed.contains(command.id), case .reply = command.kind else { return false }
            return true
        }
        let applied = Set(snapshot.applied)
        pending.removeAll { applied.contains($0.id) || now.timeIntervalSince($0.madeAt) > Self.pendingLifetime }
    }

    public mutating func perform(_ command: WristCommand) {
        pending.append(command)
    }

    /// The reader saw that `command` didn't go.
    public mutating func forget(_ command: WristCommand) {
        undelivered.removeAll { $0.id == command.id }
    }

    /// Takes back `command`. Its effect goes at once; the returned inverse is for the iPhone, which may have run it
    /// already. `nil` for a command with no inverse, whose effect just goes.
    public mutating func undo(_ command: WristCommand, now: Date) -> WristCommand? {
        pending.removeAll { $0.id == command.id }
        guard let inverse = command.inverse(madeAt: now) else { return nil }
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
        case .archive, .trash, .snooze:
            result.rows.removeAll { threads.contains($0.id) }
        case .moveToInbox, .untrash, .unsnooze, .reply:
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
