import XCTest

// A busy Mac (an archive, other simulators) can take seconds to settle a list or apply a tap, and now and then
// delivers a synthesized gesture too short to count. So a test waits for the state it checks instead of reading it
// right after the gesture, and makes a gesture again only when the state it was for never came.

/// Polls `condition` until it holds or `timeout` seconds pass, and returns whether it held.
@MainActor
func waitUntil(timeout: TimeInterval = 10, _ condition: () -> Bool) -> Bool {
    let deadline = Date.now.addingTimeInterval(timeout)
    while !condition() {
        guard Date.now < deadline else { return false }
        RunLoop.current.run(until: .now.addingTimeInterval(0.2))
    }
    return true
}

/// Makes `gesture` until `done` holds, giving each one `timeout` seconds to take effect, up to `attempts` times, and
/// returns whether it held. A gesture that arrived too short leaves things as they were, so making it again is
/// the same input, not a second action.
@MainActor
func retry(
    _ gesture: () -> Void, until done: () -> Bool, attempts: Int = 3, timeout: TimeInterval = 5
) -> Bool {
    for _ in 0..<attempts {
        gesture()
        if waitUntil(timeout: timeout, done) { return true }
    }
    return false
}

extension XCUIElement {
    /// Waits until this element's frame reads the same twice, `interval` seconds apart, and returns whether it did
    /// within `timeout`: the list it sits in has stopped moving.
    @MainActor
    func waitUntilStill(interval: TimeInterval = 0.4, timeout: TimeInterval = 10) -> Bool {
        let deadline = Date.now.addingTimeInterval(timeout)
        var last = frame
        while Date.now < deadline {
            RunLoop.current.run(until: .now.addingTimeInterval(interval))
            let now = frame
            if now == last { return true }
            last = now
        }
        return false
    }

    /// Swipes `app` up until this element takes touches, and returns whether it does. Each look gives the list two
    /// seconds to come to rest, so a busy simulator still scrolling doesn't read as the element being off screen.
    @MainActor
    func scrollIntoView(in app: XCUIApplication, swipes: Int = 8) -> Bool {
        wait(for: \.isHittable, toEqual: true, timeout: 2)
            || retry({ app.swipeUp() }, until: { isHittable }, attempts: swipes, timeout: 2)
    }
}
