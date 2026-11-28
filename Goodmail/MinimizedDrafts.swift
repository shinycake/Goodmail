import MailCore
import MailStore
import MailUI
import OSLog

/// Keeps each window's minimized messages in the database, so the bar comes back after the app is closed. One per
/// app; each window names itself with an identifier of its own, fresh every launch.
///
/// Writes start off the main actor at once, so the one made as the app leaves the screen lands before it can be
/// closed, even while the main actor is busy putting the screen away. `MinimizedDraftStore` applies them in the
/// order they were asked for.
final class MinimizedDrafts {
    private let store: MinimizedDraftStore
    /// Counts the changes asked for, so a slower write never overwrites a newer one.
    private var version = 0
    /// Each window from when it is asked for, or opens, until it closes, with what was dropped for a message moving
    /// into a window of its own and the read of a window's messages under way. Each window holds its own ticket to its
    /// name, so a window closing never changes what another window of that name holds.
    private var windows = MinimizedDraftWindows<SharedItems.Loaded, Task<Void, Never>>()

    init(database: MailDatabase) {
        store = MinimizedDraftStore(database: database)
    }

    /// Hands `ticket`'s window the drafts minimized in windows no longer open, after a launch all of them, with what
    /// was dropped for any of them, under the name of the window it was dropped for (`ComposeWindow.key`).
    func claim(
        for ticket: DraftWindowTicket, then restore: @escaping ([Draft], [String: SharedItems.Loaded]) -> Void
    ) {
        let replaced = windows.claim(ticket) { sparing in
            Task { [weak self, store] in
                let drafts = await BackgroundDatabaseWork.shared.run("Restoring minimized drafts") {
                    await Self.claim(from: store, for: ticket.window, sparing: sparing)
                }
                guard let self, case .delivered(let dropped) = windows.finishedReading(ticket) else { return }
                restore(drafts, dropped)
            }
        }
        replaced?.cancel()
    }

    /// Keeps `draft` under `ticket`'s name before its window has connected, as a message moving into a window of its
    /// own, with what was dropped for it, `loaded`, which that window takes with it (`take(for:then:)`). No other
    /// window claims the message meanwhile.
    func reserve(_ ticket: DraftWindowTicket, keeping draft: Draft, holding loaded: SharedItems.Loaded?) {
        windows.reserve(ticket, holding: loaded)?.cancel()
        keep([draft], for: ticket)
    }

    /// The window `reserve(_:keeping:holding:)` asked for won't open: its message and what was held for it go.
    func withdraw(_ ticket: DraftWindowTicket) {
        keep([], for: ticket)
        close(ticket)
    }

    /// Hands `ticket`'s window the messages kept under its name alone, taking no other window's, with what was dropped
    /// for them when the window was reserved or before the system put it away: a window that holds one message.
    func take(for ticket: DraftWindowTicket, then restore: @escaping ([Draft], SharedItems.Loaded?) -> Void) {
        let replaced = windows.take(ticket) {
            Task { [weak self, store] in
                let drafts = await BackgroundDatabaseWork.shared.run("Reading a window's message") {
                    await Self.drafts(of: ticket.window, in: store)
                }
                guard let self, case .delivered(let dropped) = windows.finishedReading(ticket) else { return }
                restore(drafts, dropped[ticket.window])
            }
        }
        replaced?.cancel()
    }

    /// Makes `drafts` the minimized messages under `ticket`'s name, unless another window holds that name now, as a
    /// message window Undo Send reopened while this one closed. The app keeps itself awake for a few seconds after it
    /// leaves the screen, which covers the write made then.
    func keep(_ drafts: [Draft], for ticket: DraftWindowTicket) {
        guard windows.owns(ticket) else { return }
        version += 1
        // Unowned on purpose. Safe: nothing may cancel it, as a write cut short would lose the message as written, the
        // one made as the app leaves the screen above all; the store applies only the newest `version` asked for, so
        // one finishing late never undoes a later one; and it logs its own failure, with nothing to hand back.
        Task { @concurrent [store, version] in
            await Self.keep(drafts, for: ticket.window, version: version, in: store)
        }
    }

    /// `ticket`'s window closed. Its drafts stay, for the next window to take; what was held for it goes, or, while
    /// its read hadn't delivered it, waits for the window to come back (`discard(_:)`).
    func close(_ ticket: DraftWindowTicket) {
        windows.close(ticket)?.cancel()
    }

    /// The system discarded `ticket`'s window, which won't come back: what waited for it goes.
    func discard(_ ticket: DraftWindowTicket) {
        windows.discard(ticket)
    }

    @concurrent private static func claim(
        from store: MinimizedDraftStore, for window: String, sparing: Set<String>
    ) async -> [Draft] {
        do {
            return try await store.claim(for: window, sparing: sparing)
        } catch {
            log.error("Couldn't read the minimized drafts: \(error, privacy: .private)")
            return []
        }
    }

    @concurrent private static func drafts(of window: String, in store: MinimizedDraftStore) async -> [Draft] {
        do {
            return try await store.drafts(of: window)
        } catch {
            log.error("Couldn't read a window's message: \(error, privacy: .private)")
            return []
        }
    }

    @concurrent private static func keep(
        _ drafts: [Draft], for window: String, version: Int, in store: MinimizedDraftStore
    ) async {
        do {
            try await store.keep(drafts, for: window, version: version)
        } catch {
            log.error("Couldn't keep the minimized drafts: \(error, privacy: .private)")
        }
    }

    nonisolated private static let log = Logger(subsystem: "com.idanbirman.goodmail", category: "drafts")
}
