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

    /// How long a sent message waits before it goes, so it can be taken back.
    public static let undoSendDelay: Duration = .seconds(10)

    /// Opens a taken-back message in the composer again.
    @ObservationIgnored public var reopen: ((Draft) -> Void)?

    public private(set) var toast: Toast?
    /// A failure to apply or undo an action locally.
    public private(set) var error: (any Error)?
    @ObservationIgnored private let commands: MailCommands
    @ObservationIgnored private var lastUndo: Undo?
    @ObservationIgnored private let toastDuration: Duration

    public init(commands: MailCommands, toastDuration: Duration = .seconds(5)) {
        self.commands = commands
        self.toastDuration = toastDuration
    }

    public func perform(_ action: ThreadAction, on threads: [ThreadSummary.ID]) {
        do {
            let undo = try commands.perform(action, on: threads)
            guard !undo.isEmpty else { return }
            lastUndo = .actions(undo)
            if let message = Self.confirmation(for: action, count: threads.count) {
                show(Toast(message: message, undo: .actions(undo)), for: toastDuration)
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

    /// Queues a message to send after the undo window, with a toast to take it back.
    public func send(_ draft: Draft) {
        do {
            try commands.send(draft, after: Self.undoSendDelay)
            lastUndo = .send(draft.id)
            show(
                Toast(
                    message: String(
                        localized: "Sending…", bundle: .module, comment: "Toast while a message waits to go"),
                    undo: .send(draft.id)),
                for: Self.undoSendDelay)
        } catch {
            self.error = error
        }
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
