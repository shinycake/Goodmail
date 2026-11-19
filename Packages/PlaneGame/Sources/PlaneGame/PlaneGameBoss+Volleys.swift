import Foundation

#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// The shapes a boss's attacks come in: a row side by side under it, or a fan spreading from it. What it sends falls
/// at the field's pace like everything else.
extension PlaneGameBoss {
    /// Something a boss sends at the plane.
    struct Sent: Equatable, Sendable {
        let kind: PlaneGameThing.Kind
        let position: CGPoint
        /// Its sideways speed, in points a second.
        let drift: CGFloat
    }

    /// Just under it, where what it sends starts.
    var muzzle: CGPoint {
        CGPoint(x: position.x, y: position.y + radius)
    }

    /// `count` of `kind` side by side under it, `spacing` apart. Near a side the whole row moves inside the lanes,
    /// far enough for each one's swing, rather than piling its outer ones onto each other.
    func row(of kind: PlaneGameThing.Kind, count: Int, spacing: CGFloat, on field: PlaneGameField) -> [Sent] {
        let reach = kind.radius + kind.swing
        let half = CGFloat(count - 1) / 2 * spacing
        let middle = field.lanes(inset: reach + half).clamping(muzzle.x)
        let lanes = field.lanes(inset: reach)
        return (0..<count).map { index in
            let x = lanes.clamping(middle + (CGFloat(index) - CGFloat(count - 1) / 2) * spacing)
            return Sent(kind: kind, position: CGPoint(x: x, y: muzzle.y), drift: 0)
        }
    }

    /// `count` of `kind` from under it, their sideways speeds `gap` apart around `aim`.
    func fan(of kind: PlaneGameThing.Kind, count: Int, gap: CGFloat, around aim: CGFloat) -> [Sent] {
        (0..<count).map { index in
            Sent(kind: kind, position: muzzle, drift: aim + (CGFloat(index) - CGFloat(count - 1) / 2) * gap)
        }
    }
}
