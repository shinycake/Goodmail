/// Paces one account's Gmail requests to its per-user quota, which Google counts in units: most calls cost 10, a
/// send 100, and an account may spend about 250 a second. The first sync of a long window would otherwise burst
/// several hundred units a second and be turned away for a minute.
///
/// A throttle pauses every request on the account at once, for as long as Gmail asks or `pause` plus up to `jitter`,
/// since requests retrying on their own short timers keep the account over its quota.
public actor GmailQuota {
    /// The time the quota runs on, from some fixed start, and how it waits; tests pass one that never waits.
    struct Timing: Sendable {
        let now: @Sendable () -> Duration
        let sleep: @Sendable (Duration) async throws -> Void

        static var continuous: Timing {
            let start = ContinuousClock.now
            return Timing(now: { start.duration(to: .now) }, sleep: { try await Task.sleep(for: $0) })
        }
    }

    private let unitsPerSecond: Double
    private let burst: Double
    private let pause: Duration
    private let jitter: Duration
    private let timing: Timing

    /// Units the account may spend now, as of `refilledAt`.
    private var allowance: Double
    private var refilledAt: Duration = .zero
    /// No request starts before this; a throttle moves it forward.
    private var resumesAt: Duration = .zero

    public init(
        unitsPerSecond: Double = 200, burst: Double = 250, pause: Duration = .seconds(30),
        jitter: Duration = .seconds(10)
    ) {
        self.init(unitsPerSecond: unitsPerSecond, burst: burst, pause: pause, jitter: jitter, timing: .continuous)
    }

    init(unitsPerSecond: Double, burst: Double, pause: Duration, jitter: Duration, timing: Timing) {
        self.unitsPerSecond = unitsPerSecond
        self.burst = burst
        self.pause = pause
        self.jitter = jitter
        self.timing = timing
        allowance = burst
    }

    /// Waits until the account may spend `cost` units, then spends them.
    func admit(cost: Double) async throws {
        while true {
            let now = timing.now()
            if now < resumesAt {
                try await timing.sleep(resumesAt - now)
                continue
            }
            refill(at: now)
            if allowance >= cost {
                allowance -= cost
                return
            }
            try await timing.sleep(.seconds((cost - allowance) / unitsPerSecond))
        }
    }

    /// Gmail turned a request away: hold every request until `retryAfter`, or the pause, has passed. The allowance
    /// starts empty after it, so requests come back at the steady rate rather than in another burst.
    func throttled(retryAfter: Duration?) {
        let wait = retryAfter ?? pause + .seconds(Double.random(in: 0...jitter.seconds))
        resumesAt = max(resumesAt, timing.now() + wait)
        allowance = 0
        refilledAt = resumesAt
    }

    private func refill(at now: Duration) {
        guard now > refilledAt else { return }
        allowance = min(burst, allowance + (now - refilledAt).seconds * unitsPerSecond)
        refilledAt = now
    }
}

extension Duration {
    fileprivate var seconds: Double {
        let (seconds, attoseconds) = components
        return Double(seconds) + Double(attoseconds) / 1e18
    }
}
