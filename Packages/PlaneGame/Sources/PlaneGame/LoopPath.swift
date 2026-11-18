public import Foundation

// CGPoint and CGSize come with Foundation, and their Equatable conformances from CoreGraphics on Apple platforms.
#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// A plane's path from one point to another with one loop on the way, the way the doodle planes fly. The game's plane
/// flies one onto the field when it sets off.
public struct LoopPath: Equatable, Sendable {
    public let start: CGPoint
    public let end: CGPoint

    public init(from start: CGPoint, to end: CGPoint) {
        self.start = start
        self.end = end
    }

    public static let loopRadius: CGFloat = 26
    public static let duration: TimeInterval = 0.85

    /// Eases in and out. `point(at: 0) == start`, `point(at: 1) == end`; progress is clamped.
    public func point(at progress: Double) -> CGPoint {
        point(along: Self.smoothstep(progress))
    }

    /// Radians clockwise from pointing at the trailing edge.
    public func heading(at progress: Double) -> Double {
        // Taken along the eased distance, whose pace never drops to zero, so the ends have a direction too.
        let along = Self.smoothstep(progress)
        let step = 0.001
        let behind = point(along: max(along - step, 0))
        let ahead = point(along: min(along + step, 1))
        return atan2(ahead.y - behind.y, ahead.x - behind.x)
    }

    /// Where the plane is once it has covered `along` of the way, from 0 to 1. The loop turns once around the middle
    /// half, climbing first, and is closed outside it, so the ends are exactly `start` and `end`.
    private func point(along: Double) -> CGPoint {
        let straight = CGPoint(
            x: start.x * (1 - along) + end.x * along, y: start.y * (1 - along) + end.y * along)
        let loop = Self.smoothstep((along - 0.25) / 0.5)
        guard loop > 0, loop < 1 else { return straight }
        let turn = 2 * Double.pi * loop
        let forward: CGFloat = end.x < start.x ? -1 : 1
        return CGPoint(
            x: straight.x + forward * Self.loopRadius * sin(turn),
            y: straight.y - Self.loopRadius * (1 - cos(turn)))
    }

    /// 0 below 0, 1 above 1, and an S between that starts and ends flat.
    static func smoothstep(_ value: Double) -> Double {
        let clamped = min(max(value, 0), 1)
        return clamped * clamped * (3 - 2 * clamped)
    }
}
