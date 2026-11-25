import Foundation

/// A clock for toasts and sends whose time is up only when a test says so (`ring`), so nothing waits on real time.
@MainActor
final class TestAlarms {
    private var set: [(instant: ContinuousClock.Instant, wake: CheckedContinuation<Void, Never>)] = []

    /// Ends every wait still set, so no task is left waiting once the test is over. The waiting tasks hold the alarms,
    /// so they can't drain themselves as they go: a test drains them as it ends.
    func drain() {
        let ringing = set
        set.removeAll()
        for alarm in ringing { alarm.wake.resume() }
    }

    /// Stands in for sleeping until `instant`. A cancelled wait still waits to be rung, as a sleep whose time was up
    /// before it saw the cancellation would.
    func wait(until instant: ContinuousClock.Instant) async {
        await withCheckedContinuation { set.append((instant, $0)) }
    }

    /// How many waits for `instant` are set.
    func count(at instant: ContinuousClock.Instant) -> Int {
        set.count { $0.instant == instant }
    }

    /// Ends every wait for `instant`.
    func ring(_ instant: ContinuousClock.Instant) {
        let ringing = set.filter { $0.instant == instant }
        set.removeAll { $0.instant == instant }
        for alarm in ringing { alarm.wake.resume() }
    }
}
