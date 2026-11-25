public import Foundation
public import MailCore

/// What the watch shows: the iPhone's last snapshot, merged with the watch's own for the accounts it reads itself
/// (ADR-023), with the reader's changes not confirmed yet laid over it, so a swipe takes effect at once and stays in
/// effect over an older snapshot until it has run.
public struct WristMailbox: Codable, Equatable, Sendable {
    /// A change the iPhone hasn't confirmed in this long is dropped: it was lost, or the iPhone couldn't run it.
    static let pendingLifetime: TimeInterval = 24 * 60 * 60

    public private(set) var snapshot: WristSnapshot?
    /// Oldest first.
    public private(set) var pending: [WristCommand] = []
    /// Replies the iPhone couldn't send, oldest first, until the reader sends them again or lets them go.
    public private(set) var undelivered: [WristCommand] = []
    /// The replies among `undelivered` that may have gone after all: the watch couldn't ask the service.
    public private(set) var unconfirmed: Set<WristCommand.ID> = []
    /// When the reader last changed each conversation in each way through the iPhone, for `handToPhone`. Kept after
    /// the change settles, as long as a change waits.
    private var toPhone: [PhoneMark] = []
    /// The watch's own feed, once it has sent one.
    public private(set) var ownInbox: OwnInbox?
    /// What only the iPhone knows, as it last said it: kept while the iPhone is away.
    public private(set) var extras: WristExtras?

    /// The watch's own feed (ADR-023): its snapshot of the accounts it reads itself, with each account's source as
    /// the watch decided it with that snapshot. They arrive together, so neither is kept without the other.
    public struct OwnInbox: Equatable, Sendable {
        public var snapshot: WristSnapshot
        public var sources: [AccountID: WristAccountSource]

        public init(snapshot: WristSnapshot, sources: [AccountID: WristAccountSource]) {
            self.snapshot = snapshot
            self.sources = sources
        }
    }

    /// A change made through the iPhone: what it set on which conversation, and when.
    struct PhoneMark: Codable, Equatable, Sendable {
        var thread: ThreadSummary.ID
        var aspect: WristCommand.Kind.Aspect
        var madeAt: Date
    }

    /// The watch's own snapshot of the accounts it reads itself.
    public var own: WristSnapshot? { ownInbox?.snapshot }
    /// Who reads each account, as the watch last decided it: the iPhone, for all, before the watch's own feed.
    public var sources: [AccountID: WristAccountSource] { ownInbox?.sources ?? [:] }

    public init(
        snapshot: WristSnapshot? = nil, pending: [WristCommand] = [], undelivered: [WristCommand] = [],
        own: OwnInbox? = nil, extras: WristExtras? = nil
    ) {
        self.snapshot = snapshot
        self.pending = pending
        self.undelivered = undelivered
        self.ownInbox = own
        self.extras = extras ?? snapshot?.extras
    }

    private enum CodingKeys: String, CodingKey {
        case snapshot, pending, undelivered, unconfirmed, toPhone, own, sources, extras
    }

    /// A mailbox stored before `undelivered`, the watch's own feed or the marks of what went to the iPhone existed
    /// has none of them.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let own = try container.decodeIfPresent(WristSnapshot.self, forKey: .own).map { snapshot in
            OwnInbox(
                snapshot: snapshot,
                sources: try container.decodeIfPresent([AccountID: WristAccountSource].self, forKey: .sources) ?? [:])
        }
        self.init(
            snapshot: try container.decodeIfPresent(WristSnapshot.self, forKey: .snapshot),
            pending: try container.decode([WristCommand].self, forKey: .pending),
            undelivered: try container.decodeIfPresent([WristCommand].self, forKey: .undelivered) ?? [],
            own: own, extras: try container.decodeIfPresent(WristExtras.self, forKey: .extras))
        unconfirmed = try container.decodeIfPresent(Set<WristCommand.ID>.self, forKey: .unconfirmed) ?? []
        toPhone = try container.decodeIfPresent([PhoneMark].self, forKey: .toPhone) ?? []
    }

    /// Stores the own feed's snapshot and sources side by side, as builds before `OwnInbox` did, so either reads it.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(snapshot, forKey: .snapshot)
        try container.encode(pending, forKey: .pending)
        try container.encode(undelivered, forKey: .undelivered)
        if !unconfirmed.isEmpty { try container.encode(unconfirmed, forKey: .unconfirmed) }
        if !toPhone.isEmpty { try container.encode(toPhone, forKey: .toPhone) }
        try container.encodeIfPresent(ownInbox?.snapshot, forKey: .own)
        try container.encode(sources, forKey: .sources)
        try container.encodeIfPresent(extras, forKey: .extras)
    }

    /// Takes the iPhone's newest snapshot, and lets go of the changes it confirms and those too old to wait for. A
    /// reply the iPhone ran and failed to send moves to `undelivered`; other failed changes just go, and the rows show
    /// the mail as it is.
    public mutating func receive(_ snapshot: WristSnapshot, now: Date) {
        self.snapshot = snapshot
        if let extras = snapshot.extras { self.extras = extras }
        settle(by: snapshot, of: .phone, now: now)
    }

    /// Takes the watch's own newest snapshot and each account's source, and settles the changes the watch ran itself
    /// as `receive` does the iPhone's.
    public mutating func receiveOwn(_ snapshot: WristSnapshot, sources: [AccountID: WristAccountSource], now: Date) {
        ownInbox = OwnInbox(snapshot: snapshot, sources: sources)
        settle(by: snapshot, of: .watch, now: now)
    }

    /// Lets go of the changes `executor` ran, as its feed's `snapshot` says, and of those too old to wait for. Each
    /// change is settled only by the feed of the device that runs it (ADR-023).
    private mutating func settle(by snapshot: WristSnapshot, of executor: WristExecutor, now: Date) {
        let failed = Set(snapshot.failed)
        undelivered += pending.filter { command in
            guard command.executor == executor, failed.contains(command.id), case .reply = command.kind else {
                return false
            }
            return true
        }
        let applied = Set(snapshot.applied)
        pending.removeAll { command in
            (command.executor == executor && applied.contains(command.id))
                || now.timeIntervalSince(command.handedOverAt ?? command.madeAt) > Self.pendingLifetime
        }
        toPhone.removeAll { now.timeIntervalSince($0.madeAt) > Self.pendingLifetime }
    }

    /// Who runs a change of `kind` to `threads`: the watch only when it reads every one of their accounts itself.
    /// The iPhone can run any change, so a change that spans both kinds of account goes to it.
    public func executor(of kind: WristCommand.Kind, on threads: [ThreadSummary.ID]) -> WristExecutor {
        let executors = Set(
            threads.map { WristExecutor.for(kind: kind, source: sources[$0.accountID] ?? .relayed(.service)) })
        return executors == [.watch] ? .watch : .phone
    }

    /// Takes over `stored`, read at launch, keeping what arrived before it: the iPhone's snapshot and the watch's own
    /// feed, which are newer, and the changes made since launch, after those stored.
    public mutating func restore(_ stored: WristMailbox) {
        var restored = stored
        if let snapshot {
            restored.snapshot = snapshot
            restored.extras = extras
        }
        if let ownInbox { restored.ownInbox = ownInbox }
        restored.pending += pending.filter { !stored.pending.contains($0) }
        restored.undelivered += undelivered.filter { !stored.undelivered.contains($0) }
        restored.unconfirmed.formUnion(unconfirmed)
        restored.toPhone += toPhone.filter { !stored.toPhone.contains($0) }
        self = restored
    }

    /// A change the watch ran itself failed: a reply moves to `undelivered`, as one the iPhone couldn't send does.
    public mutating func couldntRun(_ command: WristCommand) {
        pending.removeAll { $0.id == command.id }
        if case .reply = command.kind, !undelivered.contains(command) { undelivered.append(command) }
    }

    /// The watch took back a reply it couldn't tell went: it moves to `undelivered`, marked as one that may have.
    public mutating func couldntConfirm(_ command: WristCommand) {
        couldntRun(command)
        if undelivered.contains(command) { unconfirmed.insert(command.id) }
    }

    /// The watch couldn't run `command` because the owner turned "Mail Without iPhone" off (ADR-023): it is the
    /// iPhone's now, in its place among the changes, and stays in effect until the iPhone's snapshot confirms it, or
    /// for as long as a change handed over `now` waits.
    /// Returns it as stamped again; `nil`, changing nothing, when the iPhone has had a change since that sets the
    /// same on one of its conversations, made no earlier, even one it ran already, as with Undo: the iPhone runs
    /// changes in the order it gets them, so this one, sent after, would undo that later one. That includes this
    /// command, handed over already.
    public mutating func handToPhone(_ command: WristCommand, now: Date) -> WristCommand? {
        if let aspect = command.kind.aspect {
            let threads = Set(command.threads)
            let overtaken = toPhone.contains { mark in
                mark.aspect == aspect && mark.madeAt >= command.madeAt && threads.contains(mark.thread)
            }
            guard !overtaken else { return nil }
        } else if pending.contains(where: { $0.id == command.id && $0.executor == .phone }) {
            return nil
        }
        var phone = command
        phone.executor = .phone
        phone.handedOverAt = now
        if let index = pending.firstIndex(where: { $0.id == command.id }) {
            pending[index] = phone
            mark(phone)
        } else {
            add(phone)
        }
        return phone
    }

    public mutating func perform(_ command: WristCommand) {
        add(command)
    }

    /// Adds `command` to `pending`, after the changes before it.
    private mutating func add(_ command: WristCommand) {
        pending.append(command)
        mark(command)
    }

    /// Marks what `command` sets, if the iPhone runs it: every change the iPhone gets passes here.
    private mutating func mark(_ command: WristCommand) {
        guard command.executor == .phone, let aspect = command.kind.aspect else { return }
        for thread in command.threads {
            toPhone.removeAll { $0.thread == thread && $0.aspect == aspect && $0.madeAt <= command.madeAt }
            if !toPhone.contains(where: { $0.thread == thread && $0.aspect == aspect }) {
                toPhone.append(PhoneMark(thread: thread, aspect: aspect, madeAt: command.madeAt))
            }
        }
    }

    /// The reader saw that `command` didn't go.
    public mutating func forget(_ command: WristCommand) {
        undelivered.removeAll { $0.id == command.id }
        unconfirmed.remove(command.id)
    }

    /// Takes back `command`. Its effect goes at once; the returned inverse is for the iPhone, which may have run it
    /// already. `nil` for a command with no inverse, whose effect just goes.
    public mutating func undo(_ command: WristCommand, now: Date) -> WristCommand? {
        pending.removeAll { $0.id == command.id }
        guard let inverse = command.inverse(madeAt: now) else { return nil }
        add(inverse)
        return inverse
    }

    /// The snapshot as the reader expects it after their changes.
    public var shown: WristSnapshot? {
        snapshot.map { phone in
            pending.reduce(WristSnapshot.merged(phone: phone, own: own, sources: sources, extras: extras)) {
                $0.applying($1)
            }
        }
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
