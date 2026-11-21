public import Foundation
public import MailCore
public import Observation

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
        /// When the toast goes, and with it the chance to undo from it.
        public let ends: ContinuousClock.Instant

        init(message: String, undo: Undo, lasting duration: Duration) {
            self.message = message
            self.undo = undo
            ends = .now + duration
        }
    }

    enum Undo: Equatable {
        case actions(MailCommands.Undo)
        /// Takes a message back during its undo-send window.
        case send(Draft.ID)
    }

    /// Opens a taken-back message in the composer again.
    @ObservationIgnored public var reopen: ((Draft) -> Void)?
    /// Plays the tap for an action the reader took, as soon as they take it.
    @ObservationIgnored var feedback: (Haptic) -> Void = { _ in }

    public private(set) var toast: Toast?
    /// A failure to apply or undo an action locally.
    public private(set) var error: (any Error)?
    @ObservationIgnored private let commands: MailCommands
    /// What Undo takes back, which outlasts the toast: a shake undoes it after the toast has gone.
    @ObservationIgnored private(set) var lastUndo: Undo?
    /// Messages the writer took back out of the queue (undo, edit, delete), so a conversation tells a reply taken
    /// back from one that went. Each is added before the queue drops it.
    @ObservationIgnored private(set) var takenBack: Set<Draft.ID> = []
    /// Applies the actions in the order they were asked for (`run`).
    @ObservationIgnored private let chain = TaskChain()
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
        feedback(.performing(action))
        apply(confirmation: Self.confirmation(for: action, count: threads.count)) {
            try await $0.perform(action, on: threads)
        }
    }

    /// Moves threads the reader sees in `mailbox` to `destination`, called `name` in the toast.
    public func move(
        _ threads: [ThreadSummary.ID], to destination: MoveDestination, named name: String, from mailbox: Mailbox
    ) {
        feedback(.putAway)
        apply(
            confirmation: String(
                localized: "\(threads.count) moved to \(name)", table: "Actions", bundle: .module,
                comment: "Toast after moving threads; the second value is the mailbox or label they went to")
        ) { try await $0.perform(.move(to: destination, from: mailbox), on: threads) }
    }

    /// Takes the threads out of the Inbox until `date`, with a toast to take that back.
    public func snooze(_ threads: [ThreadSummary.ID], until date: Date) {
        feedback(.putAway)
        apply(
            confirmation: String(
                localized: "Snoozed until \(ScheduledTime.text(for: date))", table: "Actions", bundle: .module,
                comment: "Toast after snoozing threads, with when they come back")
        ) { try await $0.snooze(threads, until: date) }
    }

    /// Pins the threads to the top of their lists, or unpins them. They stay in view, so no toast; a shake undoes it.
    public func pin(_ threads: [ThreadSummary.ID], _ pinned: Bool) {
        feedback(.change)
        apply(confirmation: nil) { try await $0.pin(threads, pinned) }
    }

    /// Puts snoozed threads back in the Inbox now, with a toast to snooze them again.
    public func unsnooze(_ threads: [ThreadSummary.ID]) {
        feedback(.change)
        apply(
            confirmation: String(
                localized: "\(threads.count) moved to Inbox", table: "Actions", bundle: .module,
                comment: "Toast after putting snoozed threads back in the Inbox")
        ) { try await $0.unsnooze(threads) }
    }

    /// Marks threads read because the reader opened them: the app's doing, not an action they took, so it plays
    /// no tap and leaves nothing to undo.
    public func markOpened(_ threads: [ThreadSummary.ID]) {
        run { _ = try await $0.perform(.markRead(true), on: threads) }
    }

    /// Undoes the most recent action, from the toast or a shake. Does nothing when there is none.
    public func undoLast() {
        run { [self] commands in
            guard let undo = lastUndo else { return }
            lastUndo = nil
            toast = nil
            feedback(.undone)
            switch undo {
            case .actions(let undo):
                try await commands.undo(undo)
            case .send(let id):
                takenBack.insert(id)
                if let draft = try await commands.cancelSend(id) { reopen?(draft) }
            }
        }
    }

    /// Keeps `draft` in the provider's Drafts.
    public func saveDraft(_ draft: Draft, _ when: DraftSave = .now) {
        switch when {
        case .now, .leaving: run { try await $0.saveDraft(draft) }
        case .asWritten: run { try await $0.autosave(draft, after: OutgoingMessage.autosaveWait) }
        }
    }

    /// Removes the provider's copy of a draft: the one it was opened from, or the one autosave kept.
    public func deleteDraft(_ draft: Draft) {
        run { try await $0.deleteDraft(draft) }
    }

    /// Queues a message to go at `time`, with a toast to take it back: for the undo window when it goes now, or
    /// for the usual toast time when it waits under Scheduled. One that goes now reads as sent at once, as a chat's
    /// does; the undo window is the writer's to use, not a wait.
    public func send(_ draft: Draft, at time: SendTime = .now) {
        feedback(.sent)
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
                            localized: "Sent", table: "Actions", bundle: .module,
                            comment: "Toast with Undo after sending a message, while it can still be taken back"),
                        undo: .send(draft.id), lasting: delay))
            case .at(let date):
                try await commands.schedule(draft, at: date)
                lastUndo = .send(draft.id)
                show(Toast(message: Self.scheduledConfirmation(for: date), undo: .send(draft.id), lasting: readingTime))
            }
        }
    }

    /// Takes a scheduled message back into the composer, out of the queue until it is sent again.
    public func editScheduled(_ id: Draft.ID) {
        run { [self] commands in
            takenBack.insert(id)
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
            takenBack.insert(message.id)
            try await commands.discardSend(message.id)
            if edit { reopen?(message.draft) }
        }
    }

    /// Waits until every action asked for so far is applied, as a test does before it reads the store.
    public func settled() async {
        await chain.settled()
    }

    /// Makes one undoable change, keeps it as the last one, and confirms it with `confirmation` when there is one.
    func apply(
        confirmation: String?, _ change: @escaping (MailCommands) async throws -> MailCommands.Undo
    ) {
        run { [self] commands in
            let undo = try await change(commands)
            guard !undo.isEmpty else { return }
            lastUndo = .actions(undo)
            if let confirmation {
                show(Toast(message: confirmation, undo: .actions(undo), lasting: readingTime))
            }
        }
    }

    /// Runs `work` after everything asked for before it, so actions apply in the order the reader gave them even
    /// though each waits for the commands actor. A failure lands in `error`.
    private func run(_ work: @escaping (MailCommands) async throws -> Void) {
        chain.run { [self] in
            do {
                try await work(commands)
            } catch {
                self.error = error
            }
        }
    }

    static func scheduledConfirmation(for date: Date) -> String {
        String(
            localized: "Scheduled for \(ScheduledTime.text(for: date))", table: "Actions", bundle: .module,
            comment: "Toast after scheduling a message, with when it goes")
    }

    public func dismissToast() {
        toast = nil
    }

    /// How long a toast stays when nothing else bounds it, longer while VoiceOver or Switch Control runs. An undo-send
    /// toast can't wait past its send, so it keeps the send's delay.
    private var readingTime: Duration {
        ToastTime.lasting(toastDuration, assistiveTechnologyRuns: SystemAccessibility.assistiveTechnologyRuns)
    }

    private func show(_ toast: Toast) {
        self.toast = toast
        Task {
            try? await Task.sleep(until: toast.ends, clock: .continuous)
            if self.toast?.id == toast.id { self.toast = nil }
        }
    }

    /// What the toast says. Actions that leave the thread in view need none: the row shows the change.
    static func confirmation(for action: ThreadAction, count: Int) -> String? {
        if action == .archive {
            return String(
                localized: "\(count) archived", table: "Actions", bundle: .module,
                comment: "Toast after archiving threads")
        }
        if action == .trash {
            return String(
                localized: "\(count) moved to Trash", table: "Actions", bundle: .module,
                comment: "Toast after trashing threads")
        }
        if action == .mute {
            return String(
                localized: "\(count) muted", table: "Actions", bundle: .module, comment: "Toast after muting threads")
        }
        if action == .reportSpam {
            return String(
                localized: "\(count) reported as spam", table: "Actions", bundle: .module,
                comment: "Toast after reporting spam")
        }
        return nil
    }
}
