/// A stretch of a motion that runs from 0 to 1: where one piece of it starts and how long it takes.
public struct MorphSpan: Equatable, Sendable {
    public let start: Double
    public let length: Double

    public init(start: Double, length: Double) {
        precondition(start >= 0 && length >= 0 && start + length <= 1 + 1e-9, "A span lies within the motion")
        self.start = start
        self.length = length
    }

    /// The same stretch with the motion run backward, so the reverse of a motion plays its pieces in reverse.
    public var mirrored: MorphSpan {
        // Its end becomes its start: measured as one sum, so a span ending at 1 starts at exactly 0.
        MorphSpan(start: max(1 - (start + length), 0), length: length)
    }
}

/// How the composer's card turns into the bar of minimized messages, as one motion. It slides down into the bar's place
/// the whole way, its grabber landing on the bar's, the screen behind it brightening along with it; the curtain over
/// the status bar goes first; the composer gives way to what the bar says only once the card is nearly there.
public enum MinimizeMorph {
    /// The card's travel: its frame, corners and scale, and the dimming behind it. A card sliding in from below or
    /// off the bottom travels over the same span.
    public static let travel = MorphSpan(start: 0, length: 1)
    /// The cover over the top of the screen while the card is open.
    public static let curtain = MorphSpan(start: 0, length: 0.2)
    /// The composer itself, showing the minimized message's title under it as it goes.
    public static let composer = MorphSpan(start: 0.8, length: 0.2)
}
