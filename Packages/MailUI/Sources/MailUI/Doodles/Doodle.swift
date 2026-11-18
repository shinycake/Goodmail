import CoreGraphics

/// One doodle and where it rests.
nonisolated struct Doodle: Sendable {
    let shape: DoodleShape
    /// Its place, as fractions of the field's width and height.
    let anchor: CGPoint
    /// Decoration, not text, so a fixed size: the doodles keep their places at every text size.
    let size: CGFloat
    let angle: Double
    /// Which of the palette's colors it is drawn in.
    let tint: Int
    let art: DoodleArt

    init(_ shape: DoodleShape, x: CGFloat, y: CGFloat, size: CGFloat, angle: Double, tint: Int) {
        self.shape = shape
        anchor = CGPoint(x: x, y: y)
        self.size = size
        self.angle = angle
        self.tint = tint
        art = shape.art
    }
}

/// Where a doodle is drawn at one instant, and how it is turned.
nonisolated struct DoodlePose: Equatable, Sendable {
    let position: CGPoint
    /// Degrees clockwise from upright, as a left-to-right layout draws it.
    let angle: Double
}

nonisolated extension DoodleScene {
    /// Where the doodle at `index` of a ring is on this stage: its place, its drift and its sway.
    func pose(of doodle: Doodle, at index: Int) -> DoodlePose {
        let phase = Double(index) * 1.7
        return DoodlePose(
            position: position(anchor: doodle.anchor, phase: phase), angle: doodle.angle + sway(phase: phase))
    }
}

nonisolated extension DoodleShape {
    /// Where its art goes on a canvas: centered on `position`, `size` points across and turned `angle` degrees as a
    /// left-to-right layout draws it. Right to left, it turns the other way, and only the plane, the one shape with a
    /// direction, is mirrored: an at sign reads the same in Hebrew. Every canvas that draws a doodle places it here,
    /// so the same doodle lands on the same pixels wherever it is drawn.
    func placement(at position: CGPoint, angle: Double, size: CGFloat, rightToLeft: Bool) -> CGAffineTransform {
        CGAffineTransform.identity
            .translatedBy(position)
            .rotated(by: (rightToLeft ? -1 : 1) * angle * .pi / 180)
            .scaledBy(x: size * (self == .plane && rightToLeft ? -1 : 1), y: size)
    }
}

nonisolated extension CGAffineTransform {
    /// Moves the origin to `point`.
    func translatedBy(_ point: CGPoint) -> CGAffineTransform { translatedBy(x: point.x, y: point.y) }
}
