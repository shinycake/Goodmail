import Foundation
import MailCore
import Observation

/// Performs the reader's actions through `MailCommands` and keeps the last one undoable, shared by every screen of
/// a window so an archive in the thread view can be undone from the list it returns to. The commands run on their
/// own actor, never on the main actor, one after another in the order they were asked for.
@Observable
public final class MailActions {
    /// A confirmation with an Undo button, for actions that take a thread out of view.
    public struct Toast: Equatable, Identifiable {
        public let id = UUID()
        public let message: String
        let undo: Undo
    }

    enum Undo: Equatable {
        case actions(MailCommands.Undo)
        /// Takes a message back during its undo-send window.
        case send(Draft.ID)
    }

    /// Opens a taken-back message in the composer again.
    @ObservationIgnored public var reopen: ((Draft) -> Void)?

    public private(set) var toast: Toast?
    /// A failure to apply or undo an action locally.
    public private(set) var error: (any Error)?
    @ObservationIgnored private let commands: MailCommands
    @ObservationIgnored private var lastUndo: Undo?
    /// The last action asked for; each waits for the one before it (`run`).
    @ObservationIgnored private var queue: Task<Void, Never>?
    @ObservationIgnored private let toastDuration: Duration
    @ObservationIgnored private let undoSendDelay: () -> Duration

    /// `undoSendDelay` is read at each send, so a change in Settings applies to the next message.
    public init(
        commands: MailCommands, toastDuration: Duration = .seconds(5),
        undoSendDelay: @escaping () -> Duration = { .seconds(Preferences.undoSendSeconds) }
    ) {
        self.commands = commands
        self.toastDuration = toastDuration
        self.undoSendDelay = undoSendDelay
    }

    public func perform(_ action: ThreadAction, on threads: [ThreadSummary.ID]) {
        apply(confirmation: Self.confirmation(for: action, count: threads.count)) {
            try await $0.perform(action, on: threads)
        }
    }

    /// Moves threads the reader sees in `mailbox` to `destination`, called `name` in the toast.
    public func move(
        _ threads: [ThreadSummary.ID], to destination: MoveDestination, named name: String, from mailbox: Mailbox
    ) {
        apply(
            confirmation: String(
                localized: "\(threads.count) moved to \(name)", bundle: .module,
                comment: "Toast after moving threads; the second value is the mailbox or label they went to")
        ) { try await $0.perform(.move(to: destination, from: mailbox), on: threads) }
    }

    /// Takes the threads out of the Inbox until `date`, with a toast to take that back.
    public func snooze(_ threads: [ThreadSummary.ID], until date: Date) {
        apply(
            confirmation: String(
                localized: "Snoozed until \(ScheduledTime.text(for: date))", bundle: .module,
                comment: "Toast after snoozing threads, with when they come back")
        ) { try await $0.snooze(threads, until: date) }
    }

    /// Puts snoozed threads back in the Inbox now, with a toast to snooze them again.
    public func unsnooze(_ threads: [ThreadSummary.ID]) {
        apply(
            confirmation: String(
                localized: "\(threads.count) moved to Inbox", bundle: .module,
                comment: "Toast after putting snoozed threads back in the Inbox")
        ) { try await $0.unsnooze(threads) }
    }

    /// Undoes the most recent action, from the toast or a shake. Does nothing when there is none.
    public func undoLast() {
        run { [self] commands in
            guard let undo = lastUndo else { return }
            lastUndo = nil
            toast = nil
            switch undo {
            case .actions(let undo):
                try await commands.undo(undo)
            case .send(let id):
                if let draft = try await commands.cancelSend(id) { reopen?(draft) }
            }
        }
    }

    /// Keeps `draft` in the provider's Drafts.
    public func saveDraft(_ draft: Draft) {
        run { try await $0.saveDraft(draft) }
    }

    /// Removes the provider's copy of a draft opened from it.
    public func deleteDraft(_ draft: Draft) {
        run { try await $0.deleteDraft(draft) }
    }

    /// Queues a message to go at `time`, with a toast to take it back: for the undo window when it goes now, or
    /// for the usual toast time when it waits under Scheduled.
    public func send(_ draft: Draft, at time: SendTime = .now) {
        run { [self] commands in
            switch time {
            case .now:
                let delay = undoSendDelay()
                try await commands.send(draft, after: delay)
                guard delay > .zero else { return }
                lastUndo = .send(draft.id)
                show(
                    Toast(
                        message: String(
                            localized: "Sending…", bundle: .module, comment: "Toast while a message waits to go"),
                        undo: .send(draft.id)),
                    for: delay)
            case .at(let date):
                try await commands.schedule(draft, at: date)
                lastUndo = .send(draft.id)
                show(
                    Toast(message: Self.scheduledConfirmation(for: date), undo: .send(draft.id)), for: toastDuration)
            }
        }
    }

    /// Takes a scheduled message back into the composer, out of the queue until it is sent again.
    public func editScheduled(_ id: Draft.ID) {
        run { [self] commands in
            if let draft = try await commands.cancelSend(id) { reopen?(draft) }
        }
    }

    /// Stops a scheduled message from going, keeping it in Drafts.
    public func unschedule(_ id: Draft.ID) {
        run { try await $0.unschedule(id) }
    }

    /// Tries a message that failed to send again, now, for the same purpose.
    public func retrySend(_ message: OutgoingMessage) {
        run { try await $0.retrySend(message) }
    }

    /// Forgets a message that failed to send. With `edit`, opens its draft in the composer again.
    public func discardSend(_ message: OutgoingMessage, edit: Bool = false) {
        run { [self] commands in
            try await commands.discardSend(message.id)
            if edit { reopen?(message.draft) }
        }
    }

    /// Waits until every action asked for so far is applied, as a test does before it reads the store.
    public func settled() async {
        await queue?.value
    }

    /// Makes one undoable change, keeps it as the last one, and confirms it with `confirmation` when there is one.
    private func apply(
        confirmation: String?, _ change: @escaping (MailCommands) async throws -> MailCommands.Undo
    ) {
        run { [self] commands in
            let undo = try await change(commands)
            guard !undo.isEmpty else { return }
            lastUndo = .actions(undo)
            if let confirmation {
                show(Toast(message: confirmation, undo: .actions(undo)), for: toastDuration)
            }
        }
    }

    /// Runs `work` after everything asked for before it, so actions apply in the order the reader gave them even
    /// though each waits for the commands actor. A failure lands in `error`.
    private func run(_ work: @escaping (MailCommands) async throws -> Void) {
        let previous = queue
        queue = Task { [self] in
            await previous?.value
            do {
                try await work(commands)
            } catch {
                self.error = error
            }
        }
    }

    static func scheduledConfirmation(for date: Date) -> String {
        String(
            localized: "Scheduled for \(ScheduledTime.text(for: date))", bundle: .module,
            comment: "Toast after scheduling a message, with when it goes")
    }

    public func dismissToast() {
        toast = nil
    }

    private func show(_ toast: Toast, for duration: Duration) {
        self.toast = toast
        Task {
            try? await Task.sleep(for: duration)
            if self.toast?.id == toast.id { self.toast = nil }
        }
    }

    /// What the toast says. Actions that leave the thread in view need none: the row shows the change.
    static func confirmation(for action: ThreadAction, count: Int) -> String? {
        if action == .archive {
            return String(localized: "\(count) archived", bundle: .module, comment: "Toast after archiving threads")
        }
        if action == .trash {
            return String(
                localized: "\(count) moved to Trash", bundle: .module, comment: "Toast after trashing threads")
        }
        if action == .reportSpam {
            return String(
                localized: "\(count) reported as spam", bundle: .module, comment: "Toast after reporting spam")
        }
        return nil
    }
}
