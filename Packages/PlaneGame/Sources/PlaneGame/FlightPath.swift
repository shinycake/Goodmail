public import Foundation

// CGPoint and CGSize come with Foundation, and their Equatable conformances from CoreGraphics on Apple platforms.
#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// A plane's path from one point to another: a cubic curve that leaves `start` toward `leaving` and comes into `end`
/// from `arriving`, both given as offsets from their ends. The plane flies one onto the field when it sets off, and the
/// screen flies one home to the envelopes.
public struct FlightPath: Equatable, Sendable {
    public let start: CGPoint
    public let end: CGPoint
    public let leaving: CGPoint
    public let arriving: CGPoint

    public init(from start: CGPoint, to end: CGPoint, leaving: CGPoint, arriving: CGPoint) {
        self.start = start
        self.end = end
        self.leaving = leaving
        self.arriving = arriving
    }

    public static let duration: TimeInterval = 0.85

    /// Eases in and out. `point(at: 0) == start`, `point(at: 1) == end`; progress is clamped.
    public func point(at progress: Double) -> CGPoint {
        // The ends are given exactly, so the plane lands on them to the last bit.
        let along = Self.smoothstep(progress)
        if along <= 0 { return start }
        if along >= 1 { return end }
        // Measured from the start, so a path whose points share an x or a y keeps it exactly.
        let t = CGFloat(along)
        let rest = 1 - t
        let (first, second, third) = (3 * rest * rest * t, 3 * rest * t * t, t * t * t)
        let toSecond = CGPoint(x: end.x + arriving.x - start.x, y: end.y + arriving.y - start.y)
        return CGPoint(
            x: start.x + first * leaving.x + second * toSecond.x + third * (end.x - start.x),
            y: start.y + first * leaving.y + second * toSecond.y + third * (end.y - start.y))
    }

    /// Radians clockwise from pointing up.
    public func heading(at progress: Double) -> Double {
        let along = CGFloat(Self.smoothstep(progress))
        let handles = controls
        let rest = 1 - along
        // The curve's direction there. Where it has none, as at an end with no handle, the way from start to end.
        let dx =
            3 * rest * rest * (handles.1.x - handles.0.x) + 6 * rest * along * (handles.2.x - handles.1.x)
            + 3 * along * along * (handles.3.x - handles.2.x)
        let dy =
            3 * rest * rest * (handles.1.y - handles.0.y) + 6 * rest * along * (handles.2.y - handles.1.y)
            + 3 * along * along * (handles.3.y - handles.2.y)
        if hypot(dx, dy) > 0.000_1 { return atan2(Double(dx), Double(-dy)) }
        guard start != end else { return 0 }
        return atan2(Double(end.x - start.x), Double(start.y - end.y))
    }

    /// The same path with its far end moved to `end`, keeping its start and both handles, as when the place it flies
    /// to moves under it.
    public func ending(at end: CGPoint) -> FlightPath {
        FlightPath(from: start, to: end, leaving: leaving, arriving: arriving)
    }

    /// The four points the curve is drawn from.
    private var controls: (CGPoint, CGPoint, CGPoint, CGPoint) {
        (
            start, CGPoint(x: start.x + leaving.x, y: start.y + leaving.y),
            CGPoint(x: end.x + arriving.x, y: end.y + arriving.y), end
        )
    }

    /// 0 below 0, 1 above 1, and an S between that starts and ends flat.
    static func smoothstep(_ value: Double) -> Double {
        let clamped = min(max(value, 0), 1)
        return clamped * clamped * (3 - 2 * clamped)
    }
}

extension FlightPath {
    /// How far the handles reach: half the way from `start` to `end`, between 80 and 160 points.
    public static func reach(from start: CGPoint, to end: CGPoint) -> CGFloat {
        min(max(hypot(end.x - start.x, end.y - start.y) / 2, 80), 160)
    }

    /// The launch, from the envelopes to the plane's starting place: up and out to the side of `lanes` with more
    /// room, round, a little under the row and up into its place from straight below, so it ends pointing up.
    public static func launch(from start: CGPoint, to end: CGPoint, lanes: ClosedRange<CGFloat>) -> FlightPath {
        let reach = reach(from: start, to: end)
        let side: CGFloat = lanes.upperBound - start.x >= start.x - lanes.lowerBound ? 1 : -1
        return FlightPath(
            from: start, to: end, leaving: CGPoint(x: side * 1.2 * reach, y: -0.8 * reach),
            arriving: CGPoint(x: 0, y: reach))
    }

    /// The landing, from where the plane is to the envelopes: straight up first, then into them from below and from
    /// the side it came from.
    public static func landing(from start: CGPoint, to end: CGPoint) -> FlightPath {
        let reach = reach(from: start, to: end)
        let side: CGFloat = start.x >= end.x ? 1 : -1
        return FlightPath(
            from: start, to: end, leaving: CGPoint(x: 0, y: -reach), arriving: CGPoint(x: side * reach, y: 0.5 * reach))
    }

    /// A straight line from `start` to `end`. From a point to itself it holds still.
    public static func straight(from start: CGPoint, to end: CGPoint) -> FlightPath {
        let third = CGPoint(x: (end.x - start.x) / 3, y: (end.y - start.y) / 3)
        return FlightPath(from: start, to: end, leaving: third, arriving: CGPoint(x: -third.x, y: -third.y))
    }
}
