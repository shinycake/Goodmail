import Foundation
import Synchronization

/// The time iOS gives the extension to finish a write as it leaves the screen, for the message kept as it is written
/// (`DraftKeeper`).
nonisolated enum ShareTime {
    /// Runs `write` on the queue iOS asks for the activity's end on, which holds its thread for a write this short, and
    /// skips it when iOS gives no time at all. iOS may call the block again, expired, while the first call is still
    /// writing: only the first call writes, and the process can be suspended as the expired call returns, the same
    /// window `ShareSession` leaves a send in.
    static func awake(running write: @escaping @Sendable () -> Void) async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            let run = FirstRun()
            ProcessInfo.processInfo.performExpiringActivity(withReason: "Keeping a shared message as a draft") {
                expired in
                guard run.claim() else { return }
                if !expired { write() }
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
