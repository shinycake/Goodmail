public import Foundation

/// Fires when `taps` taps land within `window` seconds, then starts over. Ten quick taps on the envelope pile open the
/// paper plane game.
public struct TapStreak: Equatable, Sendable {
    private let taps: Int
    private let window: TimeInterval
    /// The taps that still count, oldest first.
    private var recent: [Date] = []

    public init(taps: Int = 10, within window: TimeInterval = 3) {
        self.taps = taps
        self.window = window
    }

    /// Records a tap at `time`. True when it completes the streak.
    public mutating func tap(at time: Date) -> Bool {
        recent.removeAll { time.timeIntervalSince($0) > window }
        recent.append(time)
        guard recent.count >= taps else { return false }
        recent.removeAll()
        return true
    }
}
