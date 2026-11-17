import SwiftUI

/// A few faint, still doodles in the open corners of Settings: beside the large title, and in the room after the last
/// section. They are never drawn under a row, a header or a footer, they don't move except with the list, and they
/// leave the screen to the content at accessibility text sizes and with Increase Contrast on.
struct SettingsDoodlesModifier: ViewModifier {
    @State private var visibility = SettingsDoodleVisibility.hidden
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let isDecorated = !dynamicTypeSize.isAccessibilitySize && contrast != .increased
        content
            .contentMargins(.bottom, isDecorated ? SettingsDoodleVisibility.room : 0, for: .scrollContent)
            .onScrollGeometryChange(for: SettingsDoodleVisibility.self, of: SettingsDoodleVisibility.init) {
                visibility = $1
            }
            .scrollContentBackground(.hidden)
            .background {
                ZStack(alignment: .top) {
                    Color(uiColor: .systemGroupedBackground)
                    if isDecorated {
                        SettingsDoodleGroup(doodles: SettingsDoodle.title)
                            .offset(y: visibility.titleShift)
                            .opacity(visibility.titleOpacity)
                        SettingsDoodleGroup(doodles: SettingsDoodle.end)
                            .offset(y: visibility.endTop)
                            .opacity(visibility.endOpacity)
                    }
                }
                .ignoresSafeArea()
                .accessibilityHidden(true)
            }
    }
}

extension View {
    /// Faint doodles in the corners of the Settings list.
    func settingsDoodles() -> some View {
        modifier(SettingsDoodlesModifier())
    }
}

/// One group of doodles, drawn once: scrolling moves and fades the group without drawing it again.
private struct SettingsDoodleGroup: View {
    let doodles: [SettingsDoodle]
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
                let placed = CGAffineTransform.identity
                    .translatedBy(doodle.point(width: size.width, rightToLeft: rightToLeft))
                    .rotated(by: (rightToLeft ? -1 : 1) * doodle.angle * .pi / 180)
                    // Only the plane has a direction to mirror.
                    .scaledBy(x: doodle.size * (doodle.shape == .plane && rightToLeft ? -1 : 1), y: doodle.size)
                let art = doodle.shape.art
                context.stroke(art.line.applying(placed), with: inks[doodle.tint], style: DoodleField.line)
                context.stroke(art.dots.applying(placed), with: inks[doodle.tint], style: DoodleField.dots)
            }
        }
        .frame(height: SettingsDoodleVisibility.room)
        .allowsHitTesting(false)
    }
}

/// A doodle in a Settings corner, placed in points: from the leading edge, or with a negative `x` back from the
/// trailing one, and down from the top of its group.
nonisolated struct SettingsDoodle: Sendable {
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

    /// Beside the large title, under the close button, measured from the top of the sheet.
    static let title: [SettingsDoodle] = [
        .init(.plane, x: -50, y: 93, size: 26, angle: 0, tint: 2),
        .init(.ring, x: -92, y: 109, size: 7, angle: 0, tint: 0),
        .init(.sparkle, x: -121, y: 84, size: 13, angle: 0, tint: 1),
        .init(.star, x: -160, y: 106, size: 13, angle: 12, tint: 0),
    ]

    /// In the corners of the room after the last section.
    static let end: [SettingsDoodle] = [
        .init(.postmark, x: 54, y: 64, size: 40, angle: -8, tint: 0),
        .init(.cross, x: 112, y: 96, size: 9, angle: 20, tint: 2),
        .init(.sparkle, x: -156, y: 94, size: 13, angle: 0, tint: 2),
        .init(.star, x: -106, y: 52, size: 16, angle: -10, tint: 1),
        .init(.envelope, x: -52, y: 72, size: 34, angle: 12, tint: 0),
    ]
}
