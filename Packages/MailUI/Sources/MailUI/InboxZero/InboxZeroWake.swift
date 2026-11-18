import Foundation

/// Whether the Inbox Zero scene is moving. It drifts for a while after it arrives or is touched, then eases to a stop
/// and stops drawing, so an Inbox left open on a desk costs nothing.
nonisolated enum InboxZeroWake: Equatable, Sendable {
    /// Moving since `since`: the arrival or the last touch. `rampFrom`, when given, is when the drift began easing
    /// in from rest.
    case awake(since: Date, rampFrom: Date?)
    /// Resting, with nothing drawn until a touch.
    case asleep

    /// The drift starts to ease out this long after the last wake…
    static let restsAfter: TimeInterval = 40
    /// …and has stopped by now.
    static let sleepsAfter: TimeInterval = 45
    /// How long the drift takes to ease in.
    static let rampTime: TimeInterval = 1.2

    /// How much of the idle drift plays at `now`, from 0 to 1.
    func energy(at now: Date) -> Double {
        guard case .awake(let since, let rampFrom) = self else { return 0 }
        let easedIn = rampFrom.map { Self.smoothstep(now.timeIntervalSince($0) / Self.rampTime) } ?? 1
        let resting = now.timeIntervalSince(since) - Self.restsAfter
        return easedIn * (1 - Self.smoothstep(resting / (Self.sleepsAfter - Self.restsAfter)))
    }

    /// No plane sets off by itself from then on, so none is in the air when the scene stops.
    var quietFrom: Date {
        guard case .awake(let since, _) = self else { return .distantPast }
        return since + Self.restsAfter
    }

    /// No plane sets off by itself before this. One that set off while the scene rested would show up mid-flight as
    /// it wakes, and one just after would crowd the moment it wakes in, as when the paper plane game lands back on it.
    var passesFrom: Date {
        guard case .awake(_, let rampFrom) = self else { return .distantFuture }
        return rampFrom.map { $0 + Self.passGap } ?? .distantPast
    }

    /// How long after easing in from rest the scene keeps its sky clear.
    static let passGap: TimeInterval = 3

    /// When it goes to sleep, if it is awake.
    var sleepsAt: Date? {
        guard case .awake(let since, _) = self else { return nil }
        return since + Self.sleepsAfter
    }

    /// Woken by a touch at `now`. Asleep or already easing out, the drift eases in again from rest; still easing in,
    /// it carries on.
    func woken(at now: Date) -> InboxZeroWake {
        switch self {
        case .awake(let since, let rampFrom) where now.timeIntervalSince(since) < Self.restsAfter:
            .awake(since: now, rampFrom: rampFrom)
        case .awake, .asleep:
            .awake(since: now, rampFrom: now)
        }
    }

    private static func smoothstep(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        return t * t * (3 - 2 * t)
    }
}
