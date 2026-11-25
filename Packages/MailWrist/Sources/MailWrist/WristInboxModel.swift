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
    /// Whether the stored mailbox has been taken over.
    public private(set) var isRestored = false
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

    /// Takes over a mailbox read from the store at launch, once: the app's link and an alert or a refresh the system
    /// launched the app for may each restore it first. What arrived before it loaded stays (`WristMailbox.restore`).
    public func restore(_ stored: WristMailbox) {
        guard !isRestored else { return }
        isRestored = true
        mailbox.restore(stored)
    }

    /// A change the watch ran itself, as for an alert's action, failed: a reply shows as not sent.
    public func couldntRun(_ command: WristCommand) {
        mailbox.couldntRun(command)
        continuation.yield(Update(mailbox: mailbox, command: nil))
    }

    /// The watch took back a reply it couldn't tell went: it shows as one that may not have gone.
    public func couldntConfirm(_ command: WristCommand) {
        mailbox.couldntConfirm(command)
        continuation.yield(Update(mailbox: mailbox, command: nil))
    }

    /// Whether the reply `command`, among `undelivered`, may have gone after all.
    public func mayHaveGone(_ command: WristCommand) -> Bool {
        mailbox.unconfirmed.contains(command.id)
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

    /// The watch couldn't run `command` because the owner turned "Mail Without iPhone" off since it was made: the
    /// iPhone runs it instead, as the same command, so it still runs once, unless a later change to its threads
    /// already went to the iPhone (`WristMailbox.handToPhone`).
    public func handToPhone(_ command: WristCommand) {
        guard let phone = mailbox.handToPhone(command, now: now()) else { return }
        if undoable?.id == command.id { undoable = phone }
        continuation.yield(Update(mailbox: mailbox, command: phone))
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
