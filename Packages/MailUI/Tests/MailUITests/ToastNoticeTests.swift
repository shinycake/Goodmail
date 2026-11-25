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
        #expect(actions.toast?.id == confirmation?.id, "its Undo stays")
        #expect(actions.toast?.offersUndo == true)
        actions.dismissToast()
        #expect(actions.toast?.message == "Gone")
        #expect(actions.toast?.offersUndo == false)
    }

    @Test func aNoticeWaitingWaitsBehindTheConfirmationThatReplacesItsOwn() async {
        let actions = await archived()
        actions.say("Gone")
        actions.perform(.trash, on: [thread])
        await actions.settled()
        #expect(actions.toast?.offersUndo == true)
        actions.dismissToast()
        #expect(actions.toast?.message == "Gone", "it comes up once the last confirmation goes")
    }

    @Test func aReplacedToastsTimeCannotEndItsReplacement() async throws {
        let alarms = TestAlarms()
        defer { alarms.drain() }
        let actions = MailActions(
            commands: MailCommands(store: NoStore(), replay: { _ in }), toastDuration: .seconds(60),
            wait: { await alarms.wait(until: $0) })
        actions.say("First")
        let first = try #require(actions.toast)
        actions.say("Second")
        let second = try #require(actions.toast)
        while alarms.count(at: first.ends) == 0 { await Task.yield() }
        alarms.ring(first.ends)
        for _ in 0..<20 { await Task.yield() }
        #expect(actions.toast?.id == second.id, "the first toast's time running out ends nothing now")
        while alarms.count(at: second.ends) == 0 { await Task.yield() }
        alarms.ring(second.ends)
        while actions.toast != nil { await Task.yield() }
    }

    @Test func aNoticeFollowsAnUndo() async {
        let actions = await archived()
        actions.say("Gone")
        actions.undoLast()
        await actions.settled()
        #expect(actions.toast?.message == "Gone")
    }
}
