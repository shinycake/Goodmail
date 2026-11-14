import MailCore
import Testing

@testable import MailUI

@MainActor
struct StowTests {
    @Test(arguments: [(ThreadAction.trash, StowKind.trash), (.archive, .archive)])
    func actionsThatPutAThreadAwayGoIntoTheirBox(action: ThreadAction, box: StowKind) {
        #expect(action.stow == box)
    }

    @Test(arguments: [
        ThreadAction.untrash, .moveToInbox, .reportSpam, .mute, .unmute, .markRead(true), .star(true),
    ])
    func otherActionsJustCloseTheButtons(action: ThreadAction) {
        #expect(action.stow == nil)
    }
}
