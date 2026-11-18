import Testing

@testable import MailUI

/// Drawing the game out of sight before the first game.
@MainActor
struct PlaneGameWarmUpTests {
    @Test func warmingUpDrawsTheGameWithoutAWindowAndCanBeAskedAgain() {
        PlaneGameWarmUp.run()
        PlaneGameWarmUp.run()
    }
}
