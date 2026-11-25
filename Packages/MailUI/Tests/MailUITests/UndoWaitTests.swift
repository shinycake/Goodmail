import Foundation
import MailCore
import Testing

@testable import MailUI

/// A window that stays open after its screen is done offers the toast's Undo until it goes, and learns how it went.
@MainActor
struct UndoWaitTests {
    private let draft = Draft(accountID: AccountID(rawValue: "a"), subject: "Hello")

    private func actions(undoSendDelay: Duration) -> MailActions {
        MailActions(
            commands: MailCommands(store: OutgoingQueue(), replay: { _ in }), undoSendDelay: { undoSendDelay })
    }

    @Test func `with Undo Send off there is nothing to wait for`() async {
        let actions = actions(undoSendDelay: .zero)
        var offered: [String] = []
        actions.send(draft)
        #expect(await actions.waitOutUndo { offered.append($0.message) } == .nothingToUndo)
        #expect(offered.isEmpty)
    }

    @Test func `Undo from the offered toast takes the message back into the composer`() async {
        let actions = actions(undoSendDelay: .seconds(60))
        var reopened: [Draft] = []
        actions.reopen = { reopened.append($0) }
        var offered: [String] = []
        actions.send(draft)
        let outcome = await actions.waitOutUndo { toast in
            offered.append(toast.message)
            actions.undoLast()
        }
        #expect(outcome == .undone)
        #expect(offered == ["Sent"])
        #expect(reopened == [draft], "back by the time the wait returns")
    }

    @Test func `the toast running out ends the wait with the message sent`() async {
        let actions = actions(undoSendDelay: .milliseconds(20))
        var reopened: [Draft] = []
        actions.reopen = { reopened.append($0) }
        actions.send(draft)
        #expect(await actions.waitOutUndo { _ in } == .ended)
        #expect(actions.toast == nil)
        #expect(reopened.isEmpty)
    }

    @Test func `once the message has gone Edit Undo no longer offers it back`() async {
        let actions = actions(undoSendDelay: .milliseconds(20))
        let manager = UndoManager()
        manager.groupsByEvent = false
        actions.undoManager = manager
        actions.send(draft)
        await actions.settled()
        #expect(manager.canUndo, "while it can still be taken back")
        #expect(await actions.waitOutUndo { _ in } == .ended)
        #expect(!manager.canUndo)
    }

    @Test func `a sent message stops being offered back once it goes even with its toast dismissed`() async throws {
        let alarms = TestAlarms()
        defer { alarms.drain() }
        let actions = MailActions(
            commands: MailCommands(store: OutgoingQueue(), replay: { _ in }), undoSendDelay: { .seconds(60) },
            wait: { await alarms.wait(until: $0) })
        actions.send(draft)
        await actions.settled()
        let ends = try #require(actions.toast?.ends)
        actions.dismissToast()
        #expect(actions.lastUndo == .send(draft.id), "a shake still takes it back while it waits")
        // The send's lapse and the dismissed toast's own end both wait for the same time.
        while alarms.count(at: ends) < 2 { await Task.yield() }
        alarms.ring(ends)
        for _ in 0..<20 where actions.lastUndo != nil { await Task.yield() }
        #expect(actions.undoOffer == .lapsed)
    }
}
