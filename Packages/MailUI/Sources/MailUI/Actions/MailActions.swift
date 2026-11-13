import Foundation
import MailCore
import Observation

/// Performs the reader's actions through `MailCommands` and keeps the last one undoable, shared by every screen of
/// a window so an archive in the thread view can be undone from the list it returns to.
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
        perform(action, on: threads, confirmation: Self.confirmation(for: action, count: threads.count))
    }

    /// Moves threads the reader sees in `mailbox` to `destination`, called `name` in the toast.
    public func move(
        _ threads: [ThreadSummary.ID], to destination: MoveDestination, named name: String, from mailbox: Mailbox
    ) {
        perform(
            .move(to: destination, from: mailbox), on: threads,
            confirmation: String(
                localized: "\(threads.count) moved to \(name)", bundle: .module,
                comment: "Toast after moving threads; the second value is the mailbox or label they went to"))
    }

    private func perform(_ action: ThreadAction, on threads: [ThreadSummary.ID], confirmation: String?) {
        do {
            let undo = try commands.perform(action, on: threads)
            guard !undo.isEmpty else { return }
            lastUndo = .actions(undo)
            if let confirmation {
                show(Toast(message: confirmation, undo: .actions(undo)), for: toastDuration)
            }
        } catch {
            self.error = error
        }
    }

    /// Undoes the most recent action, from the toast or a shake. Does nothing when there is none.
    public func undoLast() {
        guard let undo = lastUndo else { return }
        lastUndo = nil
        toast = nil
        do {
            switch undo {
            case .actions(let undo):
                try commands.undo(undo)
            case .send(let id):
                if let draft = try commands.cancelSend(id) { reopen?(draft) }
            }
        } catch {
            self.error = error
        }
    }

    /// Keeps `draft` in the provider's Drafts.
    public func saveDraft(_ draft: Draft) {
        do {
            try commands.saveDraft(draft)
        } catch {
            self.error = error
        }
    }

    /// Removes the provider's copy of a draft opened from it.
    public func deleteDraft(_ draft: Draft) {
        do {
            try commands.deleteDraft(draft)
        } catch {
            self.error = error
        }
    }

    /// Queues a message to go at `time`, with a toast to take it back: for the undo window when it goes now, or
    /// for the usual toast time when it waits under Scheduled.
    public func send(_ draft: Draft, at time: SendTime = .now) {
        do {
            switch time {
            case .now:
                let delay = undoSendDelay()
                try commands.send(draft, after: delay)
                guard delay > .zero else { return }
                lastUndo = .send(draft.id)
                show(
                    Toast(
                        message: String(
                            localized: "Sending…", bundle: .module, comment: "Toast while a message waits to go"),
                        undo: .send(draft.id)),
                    for: delay)
            case .at(let date):
                try commands.schedule(draft, at: date)
                lastUndo = .send(draft.id)
                show(
                    Toast(message: Self.scheduledConfirmation(for: date), undo: .send(draft.id)), for: toastDuration)
            }
        } catch {
            self.error = error
        }
    }

    /// Takes a scheduled message back into the composer, out of the queue until it is sent again.
    public func editScheduled(_ id: Draft.ID) {
        do {
            if let draft = try commands.cancelSend(id) { reopen?(draft) }
        } catch {
            self.error = error
        }
    }

    /// Stops a scheduled message from going, keeping it in Drafts.
    public func unschedule(_ id: Draft.ID) {
        do {
            try commands.unschedule(id)
        } catch {
            self.error = error
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
