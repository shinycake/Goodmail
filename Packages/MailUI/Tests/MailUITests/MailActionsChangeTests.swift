import Foundation
import MailCore
import Testing

@testable import MailUI

/// The window hears of each change the reader asks of conversations, at once and before it applies, so it moves the
/// reader in the same step (R7). What the app does by itself, as marking an opened conversation read, says nothing.
@MainActor
struct MailActionsChangeTests {
    private let thread = ThreadSummary.ID(accountID: AccountID(rawValue: "a1"), threadID: "t1")

    /// Actions whose store has nothing, and the changes they told of.
    private func actions() -> (MailActions, Changes) {
        let actions = MailActions(commands: MailCommands(store: NoStore(), replay: { _ in }))
        let changes = Changes()
        actions.changed = { changes.all.append($0) }
        return (actions, changes)
    }

    private final class Changes {
        var all: [MailChange] = []
    }

    @Test func eachChangeIsToldAsItIsAsked() {
        let (actions, changes) = actions()
        let date = Date(timeIntervalSince1970: 1_800_000_000)

        actions.perform(.archive, on: [thread])
        actions.move([thread], to: .label("Label_1"), named: "Clients", from: .inbox)
        actions.snooze([thread], until: date)
        actions.unsnooze([thread])
        actions.addLabel("Label_2", named: "Work", to: [thread])

        #expect(
            changes.all == [
                MailChange(.action(.archive), on: [thread]),
                MailChange(.move(.label("Label_1"), from: .inbox), on: [thread]),
                MailChange(.snooze, on: [thread]),
                MailChange(.unsnooze, on: [thread]),
                MailChange(.action(.modifyLabels(add: ["Label_2"], remove: [])), on: [thread]),
            ])
    }

    @Test func whatTheAppDoesByItselfOrLeavesInViewSaysNothing() async {
        let (actions, changes) = actions()
        actions.markOpened([thread])
        actions.pin([thread], true)
        await actions.settled()
        #expect(changes.all.isEmpty)
    }
}
