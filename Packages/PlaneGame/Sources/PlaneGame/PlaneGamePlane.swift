public import Foundation

// CGPoint and CGSize come with Foundation, and their Equatable conformances from CoreGraphics on Apple platforms.
#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// The reader's plane.
public struct PlaneGamePlane: Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        /// Flying its path onto the field. `elapsed` is negative while it waits to set off.
        case launching(FlightPath, elapsed: TimeInterval)
        case flying
        /// Just hit: it can't be hit again for `remaining` seconds.
        case shaken(remaining: TimeInterval)
        /// Out of lives and falling.
        case down(elapsed: TimeInterval)
    }

    public var position: CGPoint
    /// Radians clockwise from pointing up.
    public var heading: Double
    /// Where it has just been, nearest first, at most 14 points, carried down by the scroll.
    public var trail: [CGPoint]
    public var status: Status
}

/// How a new plane comes onto the field.
public enum PlaneGameLaunch: Equatable, Sendable {
    /// Unfolded from the envelopes at `point`: it swoops up, round and into its place.
    case unfolding(at: CGPoint)
    /// Straight up from below the bottom edge, as after Play Again.
    case fromBelow
    /// Already in its place, as with Reduce Motion on.
    case inPlace

    /// The path it flies onto `field`.
    func path(onto field: PlaneGameField) -> FlightPath {
        let end = field.startingPlace
        return switch self {
        case .unfolding(let point): .launch(from: point, to: end, lanes: field.lanes)
        case .fromBelow:
            .straight(from: CGPoint(x: end.x, y: field.size.height + PlaneGameRules.belowField), to: end)
        case .inPlace: .straight(from: end, to: end)
        }
    }
}
