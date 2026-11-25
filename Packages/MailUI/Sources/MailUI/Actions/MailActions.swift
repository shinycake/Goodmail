public import Foundation
public import MailCore
public import Observation

/// Performs the reader's actions through `MailCommands` and keeps the last one undoable, shared by every screen of
/// a window so an archive in the thread view can be undone from the list it returns to. The commands run on their
/// own actor, never on the main actor, one after another in the order they were asked for.
@Observable
public final class MailActions {
    /// A confirmation with an Undo button, for actions that take a thread out of view, or a notice with none.
    public struct Toast: Equatable, Identifiable {
        /// What a toast is for.
        enum Kind: Equatable {
            /// Confirms what was done, with an Undo button that takes `Undo` back. `noticeAfter` is the last notice
            /// said while it shows, which comes up once it goes rather than take its Undo away.
            case confirmation(Undo, noticeAfter: String? = nil)
            /// Tells the reader something, with no button.
            case notice
        }

        public let id: UUID
        public let message: String
        let kind: Kind
        /// When the toast goes, and with it the chance to undo from it.
        public let ends: ContinuousClock.Instant

        init(message: String, _ kind: Kind, lasting duration: Duration) {
            id = UUID()
            self.message = message
            self.kind = kind
            ends = .now + duration
        }

        /// The same toast, with `notice` to come up once it goes; a notice has nothing to wait behind it.
        func noticing(_ notice: String) -> Toast? {
            guard case .confirmation(let undo, _) = kind else { return nil }
            return Toast(id: id, message: message, kind: .confirmation(undo, noticeAfter: notice), ends: ends)
        }

        private init(id: UUID, message: String, kind: Kind, ends: ContinuousClock.Instant) {
            self.id = id
            self.message = message
            self.kind = kind
            self.ends = ends
        }

        /// Whether it offers Undo.
        var offersUndo: Bool {
            if case .confirmation = kind { true } else { false }
        }
    }

    enum Undo: Equatable {
        /// Takes back what `change`, the change the reader asked, did; `nil` for one the window isn't told of, as a pin.
        case actions(MailCommands.Undo, change: MailChange?)
        /// Takes a message back during its undo-send window.
        case send(Draft.ID)
    }

    /// Opens a taken-back message in the composer again.
    @ObservationIgnored public var reopen: ((Draft) -> Void)?
    /// Plays the tap for an action the reader took, as soon as they take it.
    @ObservationIgnored var feedback: (Haptic) -> Void = { _ in }
    /// Told of each change the reader asks of conversations in this window, as they ask it and before it applies, so
    /// the window moves its reader at once and for nothing else (R6, R7).
    @ObservationIgnored public var changed: ((MailChange) -> Void)?
    /// Told when Undo has taken back a change `changed` told of, so the window can bring the reader back to where it
    /// was (R9).
    @ObservationIgnored public var undone: ((MailChange) -> Void)?
    /// The last change the reader asked of conversations, and when, as `changed` hears it: whatever screen asked it, a
    /// list tells from it whether rows that leave were taken away by the reader (`RecentRemoval`). Only `apply` sets it.
    @ObservationIgnored private(set) var lastAsked: (change: MailChange, at: ContinuousClock.Instant)?

    /// What the toast shows, if anything. Only `show`, `say` and `endToast` change it.
    private var slot = ToastSlot.empty
    public var toast: Toast? { slot.toast }
    /// A failure to apply or undo an action locally.
    public private(set) var error: (any Error)?
    @ObservationIgnored private let commands: MailCommands
    /// Whether Undo can take something back, and how the last offer ended.
    enum UndoOffer: Equatable {
        /// Nothing done yet that Undo could take back.
        case none
        /// Undo takes this back, from the toast, a shake or ⌘Z, after the toast has gone too.
        case offering(Undo)
        /// Undo takes back a message sent now, until `lapse` ends the offer once it has gone. Replaced, the offer stops
        /// its lapse.
        case sending(Draft.ID, lapse: Task<Void, Never>)
        /// The reader took the last one back.
        case taken
        /// A sent message went once its wait was over, so it can't be taken back any more.
        case lapsed
    }

    /// The one place that says whether there is something to undo. Changes go through `undoLast`, `send` and `apply`.
    @ObservationIgnored private(set) var undoOffer = UndoOffer.none {
        didSet {
            if case .sending(_, let lapse) = oldValue { lapse.cancel() }
            offerUndo()
        }
    }

    /// What Undo would take back now.
    var lastUndo: Undo? {
        switch undoOffer {
        case .offering(let undo): return undo
        case .sending(let id, _): return .send(id)
        case .none, .taken, .lapsed: return nil
        }
    }
    /// The window's undo manager, where Edit > Undo and ⌘Z find the last undo (`offerUndo`).
    @ObservationIgnored public var undoManager: UndoManager? {
        didSet { offerUndo() }
    }
    /// Messages the writer took back out of the queue (undo, edit, delete), so a conversation tells a reply taken
    /// back from one that went. Each is added before the queue drops it.
    @ObservationIgnored private(set) var takenBack: Set<Draft.ID> = []
    /// Applies the actions in the order they were asked for (`run`).
    @ObservationIgnored private let chain = TaskChain()
    @ObservationIgnored private let toastDuration: Duration
    @ObservationIgnored private let undoSendDelay: () -> Duration
    /// Waits until a toast's or a send's time is up; a test's own clock stands in for the continuous one.
    @ObservationIgnored private let wait: (ContinuousClock.Instant) async throws -> Void

    /// `undoSendDelay` is read at each send, so a change in Settings applies to the next message.
    public convenience init(
        commands: MailCommands, toastDuration: Duration = .seconds(5),
        undoSendDelay: @escaping () -> Duration = { .seconds(Preferences.undoSendSeconds) }
    ) {
        self.init(
            commands: commands, toastDuration: toastDuration, undoSendDelay: undoSendDelay,
            wait: { try await Task.sleep(until: $0, clock: .continuous) })
    }

    /// `wait` stands in for the continuous clock, for a test that says when time is up.
    init(
        commands: MailCommands, toastDuration: Duration = .seconds(5),
        undoSendDelay: @escaping () -> Duration = { .seconds(Preferences.undoSendSeconds) },
        wait: @escaping (ContinuousClock.Instant) async throws -> Void
    ) {
        self.commands = commands
        self.toastDuration = toastDuration
        self.undoSendDelay = undoSendDelay
        self.wait = wait
    }

    public func perform(_ action: ThreadAction, on threads: [ThreadSummary.ID]) {
        apply(
            .action(action), on: threads, feedback: .performing(action),
            confirmation: Self.confirmation(for: action, count: threads.count)
        ) {
            try await $0.perform(action, on: threads)
        }
    }

    /// Moves threads the reader sees in `mailbox` to `destination`, called `name` in the toast.
    public func move(
        _ threads: [ThreadSummary.ID], to destination: MoveDestination, named name: String, from mailbox: Mailbox
    ) {
        apply(
            .move(destination, from: mailbox), on: threads, feedback: .putAway,
            confirmation: String(
                localized: "\(threads.count) moved to \(name)", table: "Actions", bundle: .module,
                comment: "Toast after moving threads; the second value is the mailbox or label they went to")
        ) { try await $0.perform(.move(to: destination, from: mailbox), on: threads) }
    }

    /// Takes the threads out of the Inbox until `date`, with a toast to take that back.
    public func snooze(_ threads: [ThreadSummary.ID], until date: Date) {
        apply(
            .snooze, on: threads, feedback: .putAway,
            confirmation: String(
                localized: "Snoozed until \(ScheduledTime.text(for: date))", table: "Actions", bundle: .module,
                comment: "Toast after snoozing threads, with when they come back")
        ) { try await $0.snooze(threads, until: date) }
    }

    /// Pins the threads to the top of their lists, or unpins them. They stay in view, so no toast; a shake undoes it.
    public func pin(_ threads: [ThreadSummary.ID], _ pinned: Bool) {
        apply(nil, on: threads, feedback: .change, confirmation: nil) { try await $0.pin(threads, pinned) }
    }

    /// Puts snoozed threads back in the Inbox now, with a toast to snooze them again.
    public func unsnooze(_ threads: [ThreadSummary.ID]) {
        apply(
            .unsnooze, on: threads, feedback: .change,
            confirmation: String(
                localized: "\(threads.count) moved to Inbox", table: "Actions", bundle: .module,
                comment: "Toast after moving threads to the Inbox, out of Snoozed or Spam")
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
            undoOffer = .taken
            endToast()
            feedback(.undone)
            switch undo {
            case .actions(let undo, let change):
                try await commands.undo(undo)
                if let change { undone?(change) }
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
                let toast = Toast(
                    message: String(
                        localized: "Sent", table: "Actions", bundle: .module,
                        comment: "Toast with Undo after sending a message, while it can still be taken back"),
                    .confirmation(.send(draft.id)), lasting: delay)
                // Once the wait is over the message has gone, so Edit > Undo and a shake stop offering it back,
                // whatever the toast shows by then.
                let lapse = Task { [weak self, wait] in
                    try? await wait(toast.ends)
                    guard !Task.isCancelled else { return }
                    self?.undoOffer = .lapsed
                }
                undoOffer = .sending(draft.id, lapse: lapse)
                show(toast)
            case .at(let date):
                try await commands.schedule(draft, at: date)
                undoOffer = .offering(.send(draft.id))
                show(
                    Toast(
                        message: Self.scheduledConfirmation(for: date), .confirmation(.send(draft.id)),
                        lasting: readingTime))
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

    /// Makes one undoable change the reader asked of `threads`, plays its `feedback`, keeps it as the last one, and
    /// confirms it with `confirmation` when there is one. The window hears of `request` at once, before it applies,
    /// so it moves its reader in the same step (`changed`); `nil` for a change that moves no reader, as a pin. Asked
    /// of no threads, as Delete with nothing listed picked, it does nothing at all.
    func apply(
        _ request: MailChange.Request?, on threads: [ThreadSummary.ID], feedback haptic: Haptic,
        confirmation: String?, _ change: @escaping (MailCommands) async throws -> MailCommands.Undo
    ) {
        guard !threads.isEmpty else { return }
        feedback(haptic)
        let asked = request.map { MailChange($0, on: threads) }
        if let asked {
            lastAsked = (asked, .now)
            changed?(asked)
        }
        run { [self] commands in
            let applied = try await change(commands)
            guard !applied.isEmpty else { return }
            let undo = Undo.actions(applied, change: asked)
            undoOffer = .offering(undo)
            if let confirmation {
                show(Toast(message: confirmation, .confirmation(undo), lasting: readingTime))
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
        endToast()
    }

    /// Says `notice` in the toast, with no Undo, for as long as a confirmation stays. A confirmation showing keeps its
    /// Undo: the notice follows once it goes, in place of any said before it. What the last Undo takes back stays,
    /// for a shake.
    public func say(_ notice: String) {
        if case .showing(let toast, let expiry) = slot, let waiting = toast.noticing(notice) {
            slot = .showing(waiting, expiry: expiry)
        } else {
            show(Toast(message: notice, .notice, lasting: readingTime))
        }
    }

    /// The toast goes; a notice that waited for it comes up.
    private func endToast() {
        guard case .showing(let ended, let expiry) = slot else { return }
        expiry.cancel()
        slot = .empty
        if case .confirmation(_, let notice?) = ended.kind { say(notice) }
    }

    /// How long a toast stays when nothing else bounds it, longer while VoiceOver or Switch Control runs. An undo-send
    /// toast can't wait past its send, so it keeps the send's delay.
    private var readingTime: Duration {
        ToastTime.lasting(toastDuration, assistiveTechnologyRuns: SystemAccessibility.assistiveTechnologyRuns)
    }

    /// Shows `toast` in place of what showed, until it ends. A notice waiting behind a confirmation it replaces waits
    /// behind it in turn, as only a notice can't be waited behind: `say` never lets one replace a confirmation.
    private func show(_ shown: Toast) {
        var waiting: String?
        if case .showing(let replaced, let expiry) = slot {
            expiry.cancel()
            if case .confirmation(_, let notice?) = replaced.kind { waiting = notice }
        }
        let toast = waiting.flatMap(shown.noticing) ?? shown
        let expiry = Task { [weak self, wait] in
            try? await wait(toast.ends)
            // Replaced or dismissed meanwhile, which cancels it, perhaps after its wait was over.
            guard !Task.isCancelled else { return }
            self?.endToast()
        }
        slot = .showing(toast, expiry: expiry)
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
        // Out of Spam and out of the Trash: the row leaves, so say where it went and offer it back.
        if action == .moveToInbox {
            return String(
                localized: "\(count) moved to Inbox", table: "Actions", bundle: .module,
                comment: "Toast after moving threads to the Inbox, out of Snoozed or Spam")
        }
        if action == .untrash {
            return String(
                localized: "\(count) restored", table: "Actions", bundle: .module,
                comment: "Toast after taking threads out of the Trash")
        }
        return nil
    }
}
