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
        let undo: MailCommands.Undo
    }

    public private(set) var toast: Toast?
    /// A failure to apply or undo an action locally.
    public private(set) var error: (any Error)?
    @ObservationIgnored private let commands: MailCommands
    @ObservationIgnored private var lastUndo: MailCommands.Undo?
    @ObservationIgnored private let toastDuration: Duration

    public init(commands: MailCommands, toastDuration: Duration = .seconds(5)) {
        self.commands = commands
        self.toastDuration = toastDuration
    }

    public func perform(_ action: ThreadAction, on threads: [ThreadSummary.ID]) {
        do {
            let undo = try commands.perform(action, on: threads)
            guard !undo.isEmpty else { return }
            lastUndo = undo
            if let message = Self.confirmation(for: action, count: threads.count) {
                show(Toast(message: message, undo: undo))
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
            try commands.undo(undo)
        } catch {
            self.error = error
        }
    }

    public func dismissToast() {
        toast = nil
    }

    private func show(_ toast: Toast) {
        self.toast = toast
        Task { [toastDuration] in
            try? await Task.sleep(for: toastDuration)
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
