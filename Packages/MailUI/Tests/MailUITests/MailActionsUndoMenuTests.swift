import Foundation
import MailCore
import Testing

@testable import MailUI

/// The last thing the reader can undo is offered to the window's undo manager too, so Edit > Undo names it and ⌘Z
/// takes it back on the Mac and on an iPad with a keyboard, as a shake or the toast's Undo does.
@MainActor
struct MailActionsUndoMenuTests {
    private let thread = ThreadSummary.ID(accountID: AccountID(rawValue: "a1"), threadID: "t1")

    /// Actions on one Inbox conversation, whose undo manager groups nothing by itself, as no run loop turns here.
    private func actions() -> (MailActions, UndoManager, Undone) {
        let store = LabelStore(["t1": [SystemLabel.inbox]])
        let actions = MailActions(commands: MailCommands(store: store, replay: { _ in }), toastDuration: .seconds(60))
        let manager = UndoManager()
        manager.groupsByEvent = false
        actions.undoManager = manager
        let undone = Undone()
        actions.undone = { undone.all.append($0) }
        return (actions, manager, undone)
    }

    private final class Undone {
        var all: [MailChange] = []
    }

    @Test func anArchiveIsOfferedUnderItsName() async {
        let (actions, manager, _) = actions()
        actions.perform(.archive, on: [thread])
        await actions.settled()
        #expect(manager.canUndo)
        #expect(manager.undoActionName == "Archive")
    }

    @Test func undoingFromTheMenuTakesTheChangeBack() async {
        let (actions, manager, undone) = actions()
        actions.perform(.archive, on: [thread])
        await actions.settled()
        manager.undo()
        await actions.settled()
        #expect(undone.all == [MailChange(.action(.archive), on: [thread])])
        #expect(!manager.canUndo, "nothing is left to undo")
        #expect(!manager.canRedo, "a mail action isn't done again from the menu")
    }

    @Test func undoingFromTheToastWithdrawsTheMenusOffer() async {
        let (actions, manager, _) = actions()
        actions.perform(.archive, on: [thread])
        actions.undoLast()
        await actions.settled()
        #expect(!manager.canUndo)
    }

    @Test func onlyTheLastActionIsOffered() async {
        let (actions, manager, undone) = actions()
        actions.perform(.star(true), on: [thread])
        actions.perform(.trash, on: [thread])
        await actions.settled()
        #expect(manager.undoActionName == "Trash")
        manager.undo()
        await actions.settled()
        #expect(undone.all == [MailChange(.action(.trash), on: [thread])])
        #expect(!manager.canUndo, "the star went with the chance to undo it")
    }

    @Test func eachChangeIsNamed() async {
        let (actions, manager, _) = actions()
        actions.move([thread], to: .label("Label_1"), named: "Clients", from: .inbox)
        await actions.settled()
        #expect(manager.undoActionName == "Move")
        actions.snooze([thread], until: Date(timeIntervalSince1970: 1_800_000_000))
        await actions.settled()
        #expect(manager.undoActionName == "Snooze")
        actions.pin([thread], true)
        await actions.settled()
        #expect(manager.canUndo, "a pin can be undone too")
        #expect(manager.undoActionName.isEmpty, "the menu says Undo alone for a pin, which the window isn't told of")
    }

    @Test func whatTheAppDoesByItselfOffersNothing() async {
        let (actions, manager, _) = actions()
        actions.markOpened([thread])
        await actions.settled()
        #expect(!manager.canUndo)
    }
}
