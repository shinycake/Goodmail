import XCTest

extension XCUIElement {
    /// Swipes this row left until `button` shows, and returns whether it did. On a busy machine a synthesized swipe
    /// sometimes arrives too short or too slow to pass halfway, and the row rightly springs back; that's the input,
    /// not the behavior under test.
    @MainActor
    func swipeOpen(showing button: XCUIElement) -> Bool {
        retry({ swipeLeft(velocity: .slow) }, until: { button.exists })
    }
}
