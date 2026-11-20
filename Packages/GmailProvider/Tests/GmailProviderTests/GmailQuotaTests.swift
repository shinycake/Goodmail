import Synchronization
import Testing

@testable import GmailProvider

/// A clock that never waits: sleeping moves its time forward at once and records how long it slept.
final class FakeTime: Sendable {
    private let elapsed = Mutex<Duration>(.zero)

    var now: Duration { elapsed.withLock { $0 } }

    var timing: GmailQuota.Timing {
        GmailQuota.Timing(now: { self.now }, sleep: { duration in self.elapsed.withLock { $0 += duration } })
    }
}

/// The account's pacer: the rate Gmail's per-user quota allows, and one pause for every request after a throttle.
struct GmailQuotaTests {
    private let time = FakeTime()

    private func quota(pause: Duration = .seconds(30)) -> GmailQuota {
        GmailQuota(unitsPerSecond: 200, burst: 200, pause: pause, jitter: .zero, timing: time.timing)
    }

    @Test func aBurstPastTheAllowanceIsSpreadAtTheRate() async throws {
        let quota = quota()
        for _ in 0..<50 { try await quota.admit(cost: 10) }
        // 200 units go at once; the other 300 come at 200 a second.
        #expect(time.now >= .seconds(1.5))
        #expect(time.now < .seconds(1.6))
    }

    @Test func requestsInsideTheAllowanceDoNotWait() async throws {
        let quota = quota()
        for _ in 0..<20 { try await quota.admit(cost: 10) }
        #expect(time.now == .zero)
    }

    @Test func aThrottlePausesTheNextRequest() async throws {
        let quota = quota()
        await quota.throttled(retryAfter: nil)
        try await quota.admit(cost: 10)
        #expect(time.now >= .seconds(30))
    }

    @Test func retryAfterSetsThePause() async throws {
        let quota = quota()
        await quota.throttled(retryAfter: .seconds(45))
        try await quota.admit(cost: 10)
        #expect(time.now >= .seconds(45))
        #expect(time.now < .seconds(46))
    }

    @Test func aShorterThrottleDoesNotCutAPauseShort() async throws {
        let quota = quota()
        await quota.throttled(retryAfter: .seconds(60))
        await quota.throttled(retryAfter: .seconds(5))
        try await quota.admit(cost: 10)
        #expect(time.now >= .seconds(60))
    }

    @Test func afterAPauseRequestsStartAgainAtTheRate() async throws {
        let quota = quota()
        await quota.throttled(retryAfter: nil)
        for _ in 0..<10 { try await quota.admit(cost: 10) }
        // The allowance is spent by the throttle, so ten requests after the pause take half a second.
        #expect(time.now >= .seconds(30.45))
    }
}
