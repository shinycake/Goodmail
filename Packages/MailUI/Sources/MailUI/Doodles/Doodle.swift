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

extension CGAffineTransform {
    /// Moves the origin to `point`.
    func translatedBy(_ point: CGPoint) -> CGAffineTransform { translatedBy(x: point.x, y: point.y) }
}
