public import Foundation
public import MailCore
public import Observation

/// The watch's Inbox screen: the iPhone's last snapshot, merged with the watch's own for the accounts it reads itself
/// (ADR-023), with the reader's changes laid over it, or why there is nothing to show.
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
        /// A command the reader made, if any, for its executor to run: the iPhone, or the watch's own host.
        public let command: WristCommand?
    }

    public private(set) var mailbox: WristMailbox
    /// What the list footer says about the mail the watch reads itself; `nil` while it reads none.
    public var freshness: WristFreshness?
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

    /// Takes over a mailbox read from the store at launch, unless the iPhone has already sent a newer one, keeping any
    /// change made before it loaded.
    public func restore(_ stored: WristMailbox) {
        guard mailbox.snapshot == nil else { return }
        let made = mailbox.pending
        mailbox = stored
        for command in made { mailbox.perform(command) }
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

    /// Takes the watch's own newest snapshot and each account's source.
    public func receiveOwn(_ snapshot: WristSnapshot, sources: [AccountID: WristAccountSource]) {
        mailbox.receiveOwn(snapshot, sources: sources, now: now())
        continuation.yield(Update(mailbox: mailbox, command: nil))
    }

    /// Makes a change to `rows` now, and has the iPhone, or the watch for an account it reads itself, make it to the
    /// mail. Undo offers to take it back.
    public func perform(_ kind: WristCommand.Kind, on rows: [WristRow]) {
        undoable = apply(kind, to: rows.map(\.id))
    }

    /// Marks a conversation read as it opens, as the iPhone's reader does. That isn't a change to undo.
    public func open(_ row: WristRow) {
        if row.isUnread { _ = apply(.markRead(true), to: [row.id]) }
    }

    /// Replies the iPhone couldn't send, for the reader to send again or let go.
    public var undelivered: [WristCommand] { mailbox.undelivered }

    /// Sends a reply that didn't go once more, as a new command, since the iPhone runs each command once.
    public func resend(_ command: WristCommand) {
        mailbox.forget(command)
        _ = apply(command.kind, to: command.threads)
    }

    /// Lets go of a reply that didn't go.
    public func forget(_ command: WristCommand) {
        mailbox.forget(command)
        continuation.yield(Update(mailbox: mailbox, command: nil))
    }

    /// Has the iPhone send `text` as a reply in the conversation. `WristReplyModel` held it for Undo already.
    public func reply(_ text: String, in thread: ThreadSummary.ID) {
        _ = apply(.reply(text), to: [thread])
    }

    private func apply(_ kind: WristCommand.Kind, to threads: [ThreadSummary.ID]) -> WristCommand {
        let command = WristCommand(
            threads: threads, kind: kind, madeAt: now(), executor: mailbox.executor(of: kind, on: threads))
        mailbox.perform(command)
        continuation.yield(Update(mailbox: mailbox, command: command))
        return command
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
