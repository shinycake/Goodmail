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

/// How the composer's card turns into the minimized message in the bottom bar, as one motion. It shrinks the whole
/// way, the screen behind it brightening along with it; the grabber and the bar over the status bar go first; the
/// composer gives way to the minimized message's title only once the card is nearly its size.
public enum MinimizeMorph {
    /// The card's frame, corners and scale, and the dimming behind it.
    public static let shrink = MorphSpan(start: 0, length: 1)
    /// The cover over the top of the screen while the card is open.
    public static let curtain = MorphSpan(start: 0, length: 0.2)
    /// The grabber at the card's top.
    public static let grabber = MorphSpan(start: 0, length: 0.25)
    /// The composer itself, showing the minimized message's title under it as it goes.
    public static let composer = MorphSpan(start: 0.8, length: 0.2)
}
