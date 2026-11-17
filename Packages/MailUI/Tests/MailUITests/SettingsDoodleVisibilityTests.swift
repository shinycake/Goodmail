import CoreGraphics
import Testing

@testable import MailUI

/// The Settings doodles keep to the open space at the top and bottom of the list, and are gone in between.
struct SettingsDoodleVisibilityTests {
    private let room = SettingsDoodleVisibility.room

    /// A list whose rows are `rows` tall in a sheet 800 points high under a 100-point bar, scrolled `scrolled` points.
    /// As a List reports it: the room is part of the content, and the bottom inset is the home indicator's.
    private func visibility(rows: CGFloat = 1600, scrolled: CGFloat) -> SettingsDoodleVisibility {
        SettingsDoodleVisibility(
            contentHeight: rows + room, offset: scrolled - 100, insetTop: 100, insetBottom: 34, height: 800)
    }

    @Test func atTheTopOnlyTheTitleGroupShows() {
        let top = visibility(scrolled: 0)
        #expect(top.titleOpacity == 1)
        #expect(top.titleShift == 0)
        #expect(top.endOpacity == 0)
    }

    @Test func theTitleGroupMovesWithTheListAndFadesBeforeTheTitleCollapses() {
        let early = visibility(scrolled: 18)
        #expect(early.titleShift == -18)
        #expect(early.titleOpacity > 0 && early.titleOpacity < 1)
        #expect(visibility(scrolled: SettingsDoodleVisibility.titleFade).titleOpacity == 0)
    }

    @Test func midListNothingShowsAndScrollingChangesNothing() {
        #expect(visibility(scrolled: 300) == .hidden)
        #expect(visibility(scrolled: 400) == .hidden)
    }

    @Test func atTheEndTheEndGroupShowsInTheRoomAfterTheLastSection() {
        // Scrolled to the end: the room sits right above the home indicator.
        let end = visibility(scrolled: 1600 + room + 34 - 800 + 100)
        #expect(end.endOpacity == 1)
        #expect(end.endTop == 800 - 34 - room)
        #expect(end.titleOpacity == 0)
    }

    @Test func aShortListKeepsTheEndGroupAtTheBottomOfTheScreen() {
        let short = visibility(rows: 300, scrolled: 0)
        #expect(short.endTop == 800 - 34 - room)
        #expect(short.endOpacity == 1)
    }

    @Test func pulledDownTheTitleGroupFollowsTheList() {
        let pulled = visibility(scrolled: -40)
        #expect(pulled.titleShift == 40)
        #expect(pulled.titleOpacity == 1)
    }

    @Test func doodlesMirrorInARightToLeftLanguage() {
        let doodle = SettingsDoodle(.star, x: -50, y: 10, size: 10, angle: 0, tint: 0)
        #expect(doodle.point(width: 400, rightToLeft: false) == CGPoint(x: 350, y: 10))
        #expect(doodle.point(width: 400, rightToLeft: true) == CGPoint(x: 50, y: 10))
    }
}
