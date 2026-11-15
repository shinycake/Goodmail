import Foundation

/// SVG's elliptical arcs as cubic Béziers, by the endpoint-to-center conversion in the SVG specification's
/// implementation notes (appendix B.2.4 and B.2.5).
enum SVGArc {
    /// The cubics, each spanning at most a quarter turn, that draw the arc from `start` to `end`. Empty when the
    /// arc draws nothing or degenerates to the straight line the caller adds.
    static func cubics(
        from start: VectorPoint, to end: VectorPoint, radii: (Double, Double), rotation: Double, largeArc: Bool,
        sweep: Bool
    ) -> [PathSegment] {
        var (rx, ry) = radii
        guard start != end, rx > 0, ry > 0 else { return [] }
        let phi = rotation * .pi / 180
        let (sinPhi, cosPhi) = (sin(phi), cos(phi))
        // Step 1: the start point in the ellipse's own axes, relative to the chord's midpoint.
        let dx = (start.x - end.x) / 2
        let dy = (start.y - end.y) / 2
        let x1 = cosPhi * dx + sinPhi * dy
        let y1 = -sinPhi * dx + cosPhi * dy
        // Radii too small to reach are scaled up just enough.
        let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lambda > 1 {
            rx *= lambda.squareRoot()
            ry *= lambda.squareRoot()
        }
        // Step 2: the center in the ellipse's axes.
        let numerator = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
        let denominator = rx * rx * y1 * y1 + ry * ry * x1 * x1
        var factor = (max(0, numerator) / denominator).squareRoot()
        if largeArc == sweep { factor = -factor }
        let cx1 = factor * rx * y1 / ry
        let cy1 = -factor * ry * x1 / rx
        // Step 3: the center in user space.
        let cx = cosPhi * cx1 - sinPhi * cy1 + (start.x + end.x) / 2
        let cy = sinPhi * cx1 + cosPhi * cy1 + (start.y + end.y) / 2
        // Step 4: the start angle and the sweep.
        let theta1 = angle(from: (1, 0), to: ((x1 - cx1) / rx, (y1 - cy1) / ry))
        var delta = angle(from: ((x1 - cx1) / rx, (y1 - cy1) / ry), to: ((-x1 - cx1) / rx, (-y1 - cy1) / ry))
        if !sweep, delta > 0 { delta -= 2 * .pi }
        if sweep, delta < 0 { delta += 2 * .pi }

        let pieces = max(1, Int((abs(delta) / (.pi / 2)).rounded(.up)))
        let step = delta / Double(pieces)
        // How far along the tangent a quarter-or-less arc's control points sit.
        let handle = 4 / 3 * tan(step / 4)
        func point(_ theta: Double) -> VectorPoint {
            let (x, y) = (rx * cos(theta), ry * sin(theta))
            return VectorPoint(x: cosPhi * x - sinPhi * y + cx, y: sinPhi * x + cosPhi * y + cy)
        }
        func derivative(_ theta: Double) -> VectorPoint {
            let (x, y) = (-rx * sin(theta), ry * cos(theta))
            return VectorPoint(x: cosPhi * x - sinPhi * y, y: sinPhi * x + cosPhi * y)
        }
        var curves: [PathSegment] = []
        var theta = theta1
        var from = start
        for piece in 0..<pieces {
            let next = theta + step
            let to = piece == pieces - 1 ? end : point(next)
            let (d1, d2) = (derivative(theta), derivative(next))
            curves.append(
                .cubic(
                    control1: VectorPoint(x: from.x + handle * d1.x, y: from.y + handle * d1.y),
                    control2: VectorPoint(x: to.x - handle * d2.x, y: to.y - handle * d2.y), to: to))
            theta = next
            from = to
        }
        return curves
    }

    private static func angle(from u: (Double, Double), to v: (Double, Double)) -> Double {
        atan2(u.0 * v.1 - u.1 * v.0, u.0 * v.0 + u.1 * v.1)
    }
}
