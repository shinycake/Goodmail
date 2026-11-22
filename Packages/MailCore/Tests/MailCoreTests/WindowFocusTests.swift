import Testing

@testable import MailCore

/// The app's windows in the order the reader was last in them, as on the Mac, where every open window says it is key
/// and only the order they became key in tells which is in front.
struct WindowFocusTests {
    @Test func untilAWindowBecomesKeyNoneIsKnownToBeInFront() {
        let focus = WindowFocus<String>()
        #expect(focus.front(among: ["viewer", "compose"]) == nil)
        #expect(focus.ordered(["viewer", "compose"]) == ["viewer", "compose"], "the windows keep the order given")
    }

    @Test func theWindowLastBecomeKeyIsInFrontAndTheOneBeforeItBehind() {
        var focus = WindowFocus<String>()
        let open = ["viewer", "second viewer", "compose"]
        focus.focused("viewer", open: open)
        focus.focused("second viewer", open: open)
        focus.focused("viewer", open: open)
        focus.focused("compose", open: open)
        #expect(focus.front(among: open) == "compose")
        #expect(focus.ordered(open) == ["compose", "viewer", "second viewer"])
    }

    @Test func aWindowNeverKeyComesAfterTheOthers() {
        var focus = WindowFocus<String>()
        focus.focused("compose", open: ["viewer", "compose"])
        #expect(focus.ordered(["viewer", "settings", "compose"]) == ["compose", "viewer", "settings"])
    }

    @Test func aClosedWindowIsForgotten() {
        var focus = WindowFocus<String>()
        focus.focused("compose", open: ["viewer", "compose"])
        focus.focused("viewer", open: ["viewer", "compose"])
        // The viewer closed and its place was taken, as when the reader closes the front window.
        #expect(focus.front(among: ["compose"]) == "compose", "the one behind it comes to the front")
        focus.focused("settings", open: ["compose", "settings"])
        focus.focused("compose", open: ["compose", "settings"])
        #expect(focus.ordered(["viewer", "compose", "settings"]) == ["compose", "settings", "viewer"])
    }
}
