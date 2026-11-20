import Foundation
import MailCore
import MailStore
import Synchronization

/// Keeps the message in the app's queue as it is written, so it is never lost when the sheet goes away unasked: the
/// other app quits, iOS ends the extension, or it crashes. Each version is the draft save the app's own composer
/// queues as it autosaves (`OutgoingStore.enqueueSave`), which the app takes to the provider's Drafts the next time it
/// runs. Sending or saving from the sheet takes the waiting save back first (`settle`, `take`).
///
/// Writes go one at a time, in the order they were asked for, off the main actor. Each runs inside the time iOS gives
/// a process to finish as it leaves the screen, so none holds the database when iOS suspends the extension
/// (0xdead10cc). A write iOS gives no time for is skipped: the version before it stays queued.
nonisolated final class ShareDrafts: Sendable {
    private let database: MailDatabase
    /// The last write asked for, which waits for the one before it: the chain `settle` waits on.
    private let last = Mutex<Task<Void, Never>?>(nil)

    init(database: MailDatabase) {
        self.database = database
    }

    /// Queues `draft` as written, for the app to save in Drafts by `date`: after autosave's wait while it is written,
    /// or now as the sheet leaves the screen.
    func keep(_ draft: Draft, by date: Date) {
        let database = database
        write { try? database.enqueueSave(OutgoingMessage(draft: draft, purpose: .saveDraft, sendAt: date)) }
    }

    /// The writer deleted the message: the save waiting is replaced by removing the copy, if the app already saved
    /// one, as the app's composer does (`MailCommands.deleteDraft`).
    func discard(_ draft: Draft) {
        let database = database
        write { try? database.enqueue(OutgoingMessage(draft: draft, purpose: .deleteDraft, sendAt: .now)) }
    }

    /// Waits for every write asked for so far.
    func settle() async {
        await last.withLock { $0 }?.value
    }

    /// Takes back the save waiting for `draft`, as the sheet sends or saves it itself. Call after `settle`. A save the
    /// app is uploading at that moment can't be taken back; the copy it leaves is the one the send then removes, if it
    /// is recorded by then.
    func take(_ draft: Draft.ID) {
        _ = try? database.cancel(draft)
    }

    private func write(_ work: @escaping @Sendable () -> Void) {
        last.withLock { last in
            let before = last
            last = Task {
                await before?.value
                await Self.awake(running: work)
            }
        }
    }

    /// Runs `work` on the queue iOS asks for the activity's end on, which holds its thread for a write this short.
    /// The block may be asked again, expired, while the first run is still writing; only the first run counts.
    private static func awake(running work: @escaping @Sendable () -> Void) async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            let run = FirstRun()
            ProcessInfo.processInfo.performExpiringActivity(withReason: "Keeping a shared message as a draft") {
                expired in
                guard run.claim() else { return }
                if !expired { work() }
                done.resume()
            }
        }
    }
}

/// Tells the first of several calls apart from the rest, from any thread.
nonisolated private final class FirstRun: Sendable {
    private let claimed = Mutex(false)

    /// Whether this is the first call.
    func claim() -> Bool {
        claimed.withLock { claimed in
            defer { claimed = true }
            return !claimed
        }
    }
}
