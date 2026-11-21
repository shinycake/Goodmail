import Foundation
import MailCore
import Testing

@testable import MailUI

/// A notice never takes a confirmation's Undo away: it waits for the confirmation to go, then comes up.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ToastNoticeTests {
    private let thread = ThreadSummary.ID(accountID: AccountID(rawValue: "a1"), threadID: "t1")

    private func archived() async -> MailActions {
        let store = LabelStore(["t1": ["INBOX"]])
        let actions = MailActions(commands: MailCommands(store: store, replay: { _ in }), toastDuration: .seconds(60))
        actions.perform(.archive, on: [thread])
        await actions.settled()
        return actions
    }

    @Test func aNoticeWithNothingShowingComesUpAtOnce() {
        let actions = MailActions(commands: MailCommands(store: NoStore(), replay: { _ in }))
        actions.say("Gone")
        #expect(actions.toast?.message == "Gone")
        #expect(actions.toast?.kind == .notice)
    }

    @Test func aNoticeWaitsForTheConfirmationShowing() async {
        let actions = await archived()
        let confirmation = actions.toast
        actions.say("Gone")
        #expect(actions.toast == confirmation, "its Undo stays")
        actions.dismissToast()
        #expect(actions.toast?.message == "Gone")
        #expect(actions.toast?.offersUndo == false)
    }

    @Test func aNoticeFollowsAnUndo() async {
        let actions = await archived()
        actions.say("Gone")
        actions.undoLast()
        await actions.settled()
        #expect(actions.toast?.message == "Gone")
    }
}
