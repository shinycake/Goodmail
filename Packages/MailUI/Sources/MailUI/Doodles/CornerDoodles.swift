import SwiftUI

/// One group of doodles, drawn once: scrolling moves and fades the group without drawing it again.
struct CornerDoodleGroup: View {
    let doodles: [CornerDoodle]
    /// How tall the group is: the room after a list's last section, unless it says otherwise.
    var height = CornerDoodleVisibility.room
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        let inks = DoodlePalette.washed(
            into: Color(uiColor: .systemGroupedBackground), by: colorScheme == .dark ? 0.66 : 0.74
        )
        .map { GraphicsContext.Shading.color($0) }
        let rightToLeft = layoutDirection == .rightToLeft
        Canvas { context, size in
            for doodle in doodles {
                let placed = doodle.shape.placement(
                    at: doodle.point(width: size.width, rightToLeft: rightToLeft), angle: doodle.angle,
                    size: doodle.size, rightToLeft: rightToLeft)
                let art = doodle.shape.art
                context.stroke(art.line.applying(placed), with: inks[doodle.tint], style: DoodleField.line)
                context.stroke(art.dots.applying(placed), with: inks[doodle.tint], style: DoodleField.dots)
            }
        }
        .frame(height: height)
        .allowsHitTesting(false)
    }
}

/// A doodle in a corner of a list, placed in points: from the leading edge, or with a negative `x` back from the
/// trailing one, and down from the top of its group.
nonisolated struct CornerDoodle: Sendable {
    let shape: DoodleShape
    let x: CGFloat
    let y: CGFloat
    let size: CGFloat
    let angle: Double
    let tint: Int

    init(_ shape: DoodleShape, x: CGFloat, y: CGFloat, size: CGFloat, angle: Double, tint: Int) {
        self.shape = shape
        self.x = x
        self.y = y
        self.size = size
        self.angle = angle
        self.tint = tint
    }

    /// Where it sits in a group `width` wide, mirrored for a right-to-left language.
    func point(width: CGFloat, rightToLeft: Bool) -> CGPoint {
        let leading = x >= 0 ? x : width + x
        return CGPoint(x: rightToLeft ? width - leading : leading, y: y)
    }
}

/// Whether a screen's faint corner doodles show: while the reader keeps Doodles on in Settings, and never at
/// accessibility text sizes or with Increase Contrast on, where the screen is left to its content. The welcome screen
/// and Inbox Zero don't ask: their doodles are those screens' pictures.
struct CornerDoodlesShown: DynamicProperty {
    @AppStorage(Preferences.showsDoodlesKey) private var chosen = true
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorSchemeContrast) private var contrast

    var wrappedValue: Bool { chosen && !dynamicTypeSize.isAccessibilitySize && contrast != .increased }
}
