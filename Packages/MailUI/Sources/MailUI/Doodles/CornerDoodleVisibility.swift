import CoreGraphics
import SwiftUI

/// Where a list's corner doodles are and how much of them shows, from how far the list has scrolled. The group beside the
/// large title fades before the title collapses into the bar; the group after the last section fades in as the room
/// left for it comes on screen. Mid-list both are gone, and the value stays the same while scrolling there.
nonisolated struct CornerDoodleVisibility: Equatable, Sendable {
    var titleOpacity: Double
    /// How far the title group has moved with the list, up as it scrolls.
    var titleShift: CGFloat
    var endOpacity: Double
    /// The top of the room after the last section, in the list's own coordinates.
    var endTop: CGFloat

    /// The room after the last section the end group sits in.
    static let room: CGFloat = 128
    /// The title group has faded by this much scrolling.
    static let titleFade: CGFloat = 36
    /// The end group starts to show when this much of its room is on screen, and has fully shown by `endShown`.
    static let endHidden: CGFloat = 56
    static let endShown: CGFloat = 116

    static let hidden = CornerDoodleVisibility(titleOpacity: 0, titleShift: 0, endOpacity: 0, endTop: 0)

    /// From the list's scroll geometry. `contentHeight` is its content's height, the room after the last section
    /// included: a List's content margins grow its content, not its insets. `offset` is its content offset, `insetTop`
    /// and `insetBottom` its content insets (the bars, and at the bottom the home indicator), and `height` its own.
    init(contentHeight: CGFloat, offset: CGFloat, insetTop: CGFloat, insetBottom: CGFloat, height: CGFloat) {
        let scrolled = offset + insetTop
        titleOpacity = 1 - Self.smoothstep(scrolled / Self.titleFade)
        titleShift = -scrolled
        let visibleBottom = height - insetBottom
        // A list shorter than the screen leaves its room at the bottom of the screen.
        endTop = max(contentHeight - Self.room - offset, visibleBottom - Self.room)
        endOpacity = Self.smoothstep((visibleBottom - endTop - Self.endHidden) / (Self.endShown - Self.endHidden))
        if titleOpacity == 0, endOpacity == 0 { self = .hidden }
    }

    init(titleOpacity: Double, titleShift: CGFloat, endOpacity: Double, endTop: CGFloat) {
        self.titleOpacity = titleOpacity
        self.titleShift = titleShift
        self.endOpacity = endOpacity
        self.endTop = endTop
    }

    init(_ geometry: ScrollGeometry) {
        self.init(
            contentHeight: geometry.contentSize.height, offset: geometry.contentOffset.y,
            insetTop: geometry.contentInsets.top, insetBottom: geometry.contentInsets.bottom,
            height: geometry.containerSize.height)
    }

    private static func smoothstep(_ x: CGFloat) -> Double {
        let t = Double(min(max(x, 0), 1))
        return t * t * (3 - 2 * t)
    }
}
