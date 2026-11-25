import Foundation
import MailCore
import Testing

@testable import MailUI

/// Every change the reader asks of conversations, from whatever screen, is kept as the last one asked, which a list
/// reads to tell rows the reader took away from rows a sync took (`RecentRemoval`).
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct AskedChangeTests {
    private let thread = ThreadSummary.ID(accountID: AccountID(rawValue: "a1"), threadID: "t1")

    private func actions() -> MailActions {
        MailActions(commands: MailCommands(store: LabelStore(["t1": ["INBOX"]]), replay: { _ in }))
    }

    @Test func aContextMenusSnoozeIsKept() {
        let actions = actions()
        actions.snooze([thread], until: .now + 3600)
        #expect(actions.lastAsked?.change == MailChange(.snooze, on: [thread]))
    }

    @Test func aMovePickersMoveIsKept() {
        let actions = actions()
        actions.move([thread], to: .archive, named: "Archive", from: .inbox)
        #expect(actions.lastAsked?.change == MailChange(.move(.archive, from: .inbox), on: [thread]))
    }

    @Test func aCommandOrTheReadersActionIsKept() {
        let actions = actions()
        let list = MailboxViewModel(
            accounts: [], source: .flat { AsyncThrowingStream { $0.finish() } }, refresh: {}, actions: actions)
        list.perform(.trash, on: [thread])
        #expect(actions.lastAsked?.change == MailChange(.action(.trash), on: [thread]))
    }

    @Test func aPinMovesNoRowAndIsNotKept() {
        let actions = actions()
        actions.pin([thread], true)
        #expect(actions.lastAsked == nil)
    }

    @Test func aRowTheKeptChangeTookIsTheReaders() throws {
        let actions = actions()
        actions.perform(.archive, on: [thread])
        let asked = try #require(actions.lastAsked)
        let row = ThreadSummary(
            id: thread, subject: "", snippet: "", sender: Contact(name: nil, address: "x@example.com"), date: .now,
            isUnread: false, messageCount: 1, labelIDs: [SystemLabel.inbox])
        var removal = RecentRemoval.none
        removal.rowsLeft([row], answered: true, in: .inbox, asked: asked, at: asked.at)
        #expect(removal == .took(at: asked.at))
    }
}
