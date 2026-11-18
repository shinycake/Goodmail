import SwiftUI

/// A few faint, still doodles in the open corners of Settings: beside the large title, and in the room after the last
/// section. They are never drawn under a row, a header or a footer, they don't move except with the list, and they
/// leave the screen to the content at accessibility text sizes, with Increase Contrast on, and with Doodles off.
struct SettingsDoodlesModifier: ViewModifier {
    @State private var visibility = CornerDoodleVisibility.hidden
    private var isDecorated = CornerDoodlesShown()

    func body(content: Content) -> some View {
        let isDecorated = isDecorated.wrappedValue
        content
            .contentMargins(.bottom, isDecorated ? CornerDoodleVisibility.room : 0, for: .scrollContent)
            .onScrollGeometryChange(for: CornerDoodleVisibility.self, of: CornerDoodleVisibility.init) {
                visibility = $1
            }
            .scrollContentBackground(.hidden)
            .background {
                ZStack(alignment: .top) {
                    Color(uiColor: .systemGroupedBackground)
                    if isDecorated {
                        CornerDoodleGroup(doodles: CornerDoodle.settingsTitle)
                            .offset(y: visibility.titleShift)
                            .opacity(visibility.titleOpacity)
                        CornerDoodleGroup(doodles: CornerDoodle.settingsEnd)
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

/// A tiny doodle at the far end of a section header, in the open space the header's words leave.
private struct HeaderDoodle: ViewModifier {
    let doodle: CornerDoodle
    private var isDecorated = CornerDoodlesShown()

    init(doodle: CornerDoodle) {
        self.doodle = doodle
    }

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .trailing) {
                if isDecorated.wrappedValue {
                    CornerDoodleGroup(doodles: [doodle], height: Self.height)
                        .frame(width: Self.width)
                        .accessibilityHidden(true)
                }
            }
    }

    static let width: CGFloat = 48
    static let height: CGFloat = 24
}

extension View {
    /// A tiny `shape` doodle at the far end of a Settings section header.
    func headerDoodle(_ shape: DoodleShape, size: CGFloat, angle: Double = 0, tint: Int) -> some View {
        modifier(
            HeaderDoodle(
                doodle: CornerDoodle(shape, x: -10, y: HeaderDoodle.height / 2, size: size, angle: angle, tint: tint)))
    }
}

extension CornerDoodle {
    /// Beside the large title, under the close button, measured from the top of the sheet.
    static let settingsTitle: [CornerDoodle] = [
        .init(.plane, x: -50, y: 93, size: 26, angle: 0, tint: 2),
        .init(.ring, x: -92, y: 109, size: 7, angle: 0, tint: 0),
        .init(.sparkle, x: -121, y: 84, size: 13, angle: 0, tint: 1),
        .init(.star, x: -160, y: 106, size: 13, angle: 12, tint: 0),
    ]

    /// In the corners of the room after the last section.
    static let settingsEnd: [CornerDoodle] = [
        .init(.postmark, x: 54, y: 64, size: 40, angle: -8, tint: 0),
        .init(.cross, x: 112, y: 96, size: 9, angle: 20, tint: 2),
        .init(.sparkle, x: -156, y: 94, size: 13, angle: 0, tint: 2),
        .init(.star, x: -106, y: 52, size: 16, angle: -10, tint: 1),
        .init(.envelope, x: -52, y: 72, size: 34, angle: 12, tint: 0),
    ]
}
