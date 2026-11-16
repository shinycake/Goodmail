import MailCore
import MailStore
import OSLog

/// Keeps each window's minimized messages in the database, so the bar comes back after the app is closed. One per
/// app; each window names itself with an identifier of its own, fresh every launch.
///
/// Writes start off the main actor at once, so the one made as the app leaves the screen lands before it can be
/// closed, even while the main actor is busy putting the screen away. `MinimizedDraftStore` applies them in the
/// order they were asked for.
final class MinimizedDrafts {
    private let store: MinimizedDraftStore
    /// The windows open now, whose drafts no other window takes.
    private var open: Set<String> = []
    /// Counts the changes asked for, so a slower write never overwrites a newer one.
    private var version = 0
    /// The last write asked for in each window. A newer one supersedes it.
    private var writes: [String: Task<Void, Never>] = [:]
    /// Reading back the drafts of a window opened since launch.
    private var claims: [String: Task<Void, Never>] = [:]

    init(database: MailDatabase) {
        store = MinimizedDraftStore(database: database)
    }

    /// Hands `window` the drafts minimized in windows no longer open: after a launch, all of them.
    func claim(for window: String, then restore: @escaping ([Draft]) -> Void) {
        let sparing = open
        open.insert(window)
        claims[window] = Task { [store] in
            let drafts = await BackgroundDatabaseWork.shared.run("Restoring minimized drafts") {
                await Self.claim(from: store, for: window, sparing: sparing)
            }
            guard !Task.isCancelled else { return }
            restore(drafts)
        }
    }

    /// Makes `drafts` the minimized messages of `window`. The app keeps itself awake for a few seconds after it
    /// leaves the screen, which covers the write made then.
    func keep(_ drafts: [Draft], for window: String) {
        version += 1
        writes[window] = Task { @concurrent [store, version] in
            await Self.keep(drafts, for: window, version: version, in: store)
        }
    }

    /// The window closed. Its drafts stay, for the next window to take.
    func close(_ window: String) {
        open.remove(window)
        claims[window]?.cancel()
        claims[window] = nil
        writes[window] = nil
    }

    @concurrent private static func claim(
        from store: MinimizedDraftStore, for window: String, sparing: Set<String>
    ) async -> [Draft] {
        do {
            return try await store.claim(for: window, sparing: sparing)
        } catch {
            log.error("Couldn't read the minimized drafts: \(error, privacy: .public)")
            return []
        }
    }

    @concurrent private static func keep(
        _ drafts: [Draft], for window: String, version: Int, in store: MinimizedDraftStore
    ) async {
        do {
            try await store.keep(drafts, for: window, version: version)
        } catch {
            log.error("Couldn't keep the minimized drafts: \(error, privacy: .public)")
        }
    }

    nonisolated private static let log = Logger(subsystem: "com.idanbirman.goodmail", category: "drafts")
}
