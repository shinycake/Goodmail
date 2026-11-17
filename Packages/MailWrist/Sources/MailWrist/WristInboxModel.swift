public import Foundation
public import Observation

/// The watch's Inbox screen: the iPhone's last snapshot with the reader's changes laid over it, or why there is
/// nothing to show.
@MainActor @Observable
public final class WristInboxModel {
    public enum State: Equatable, Sendable {
        /// Nothing has arrived from the iPhone yet.
        case waitingForPhone
        /// The iPhone's app is newer than this one and sends what this one can't read.
        case updateNeeded
        /// The iPhone has no mail accounts.
        case noAccounts
        /// The Inbox is empty.
        case caughtUp(WristSnapshot)
        case list(WristSnapshot)
    }

    /// Whether the last thing the iPhone sent could be read.
    private enum Reading {
        case current
        case phoneIsNewer
    }

    /// What has to reach the store and the iPhone after a change.
    public struct Update: Sendable {
        public let mailbox: WristMailbox
        /// A command for the iPhone to run, if the reader made one.
        public let command: WristCommand?
    }

    public private(set) var mailbox: WristMailbox
    private var reading = Reading.current
    /// The reader's last change, which they can take back for a few seconds.
    public private(set) var undoable: WristCommand?
    /// Each change, in order, for `WristLink` to store and send.
    public nonisolated let updates: AsyncStream<Update>
    private let continuation: AsyncStream<Update>.Continuation
    private let now: @Sendable () -> Date

    public init(mailbox: WristMailbox = WristMailbox(), now: @escaping @Sendable () -> Date = { .now }) {
        self.mailbox = mailbox
        self.now = now
        (updates, continuation) = AsyncStream.makeStream(of: Update.self)
    }

    public var state: State {
        if reading == .phoneIsNewer { return .updateNeeded }
        guard let shown = mailbox.shown else { return .waitingForPhone }
        if shown.accounts.isEmpty { return .noAccounts }
        return shown.rows.isEmpty ? .caughtUp(shown) : .list(shown)
    }

    /// Takes over a mailbox read from the store at launch, unless the iPhone has already sent a newer one.
    public func restore(_ stored: WristMailbox) {
        guard mailbox.snapshot == nil else { return }
        mailbox = stored
    }

    public func receive(_ reading: WristSnapshot.Reading) {
        switch reading {
        case .newerVersion:
            self.reading = .phoneIsNewer
        case .snapshot(let snapshot):
            self.reading = .current
            mailbox.receive(snapshot, now: now())
            continuation.yield(Update(mailbox: mailbox, command: nil))
        }
    }

    /// Makes a change to `rows` now, and has the iPhone make it to the mail.
    public func perform(_ kind: WristCommand.Kind, on rows: [WristRow]) {
        let command = WristCommand(threads: rows.map(\.id), kind: kind, madeAt: now())
        mailbox.perform(command)
        undoable = command
        continuation.yield(Update(mailbox: mailbox, command: command))
    }

    /// Takes back the last change.
    public func undo() {
        guard let undoable else { return }
        self.undoable = nil
        let inverse = mailbox.undo(undoable, now: now())
        continuation.yield(Update(mailbox: mailbox, command: inverse))
    }

    /// The time to undo `command` is over.
    public func keep(_ command: WristCommand) {
        if undoable == command { undoable = nil }
    }
}
