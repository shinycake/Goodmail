import AppIntents
import Foundation
import MailCore
import os

/// The changes one intent made, taken back when the system asks it to undo: from Undo in Shortcuts, or a shake right
/// after Siri acted. The intent has finished by then, so this object owns the work, and the undo manager holds it.
@MainActor
final class IntentUndo {
    private let host: any MailIntentsHost
    /// In the order the intent made them.
    private let changes: [MailCommands.Undo]
    /// The undo under way. Nobody waits for a system undo, so a failure is logged rather than thrown.
    private(set) var running: Task<Void, Never>?

    private static let log = Logger(subsystem: "com.idanbirman.goodmail", category: "intents")

    init(host: any MailIntentsHost, changes: [MailCommands.Undo]) {
        self.host = host
        self.changes = changes
    }

    /// Starts taking the changes back, once: the undo manager runs an undo once, and a second call does nothing.
    func start() {
        guard running == nil else { return }
        running = Task { [host, changes] in
            do {
                try await Self.takeBack(changes, through: host)
            } catch {
                Self.log.error("Couldn't undo an intent's change: \(error)")
            }
        }
    }

    /// Takes `changes` back newest first, so each one lands on the state it was made from.
    nonisolated static func takeBack(_ changes: [MailCommands.Undo], through host: any MailIntentsHost) async throws {
        for change in changes.reversed() where !change.isEmpty {
            try await host.undo(change)
        }
    }
}

extension UndoableIntent {
    /// Offers the system's Undo, named `name`, for `changes`. A change that undoes nothing offers no Undo.
    @MainActor func offerUndo(
        of changes: [MailCommands.Undo], named name: LocalizedStringResource, host: any MailIntentsHost
    ) {
        guard changes.contains(where: { !$0.isEmpty }), let undoManager else { return }
        // The undo manager holds its target unowned, so the handler keeps the undo alive until it runs.
        let undo = IntentUndo(host: host, changes: changes)
        undoManager.registerUndo(withTarget: undo) { _ in undo.start() }
        undoManager.setActionName(String(localized: name))
    }
}
