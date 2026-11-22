import Foundation
import MailCore
import Testing

@testable import MailUI

struct HoverActionsTests {
    private func thread(_ labels: Set<String>, unread: Bool = true) -> ThreadSummary {
        ThreadSummary(
            id: ThreadSummary.ID(accountID: AccountID(rawValue: "a"), threadID: "t"), subject: "", snippet: "",
            sender: Contact(name: nil, address: "x@example.com"), date: .now, isUnread: unread, messageCount: 1,
            labelIDs: labels)
    }

    private func choices(_ hover: HoverActions, _ thread: ThreadSummary, in mailbox: Mailbox = .inbox) -> [SwipeChoice]
    {
        hover.buttons(for: thread, at: ThreadPlace(thread, in: mailbox), tints: .standard).map(\.choice)
    }

    @Test func theStandardActionsAreArchiveTrashAndReadInThatOrder() {
        #expect(HoverActions.standard == .on(HoverActions.Picks([.archive, .trash, .read])))
        #expect(choices(.standard, thread(["INBOX"])) == [.archive, .trash, .read])
    }

    @Test func picksKeepTheirOrderAndStopAtThree() {
        let picks = HoverActions.Picks([.star, .snooze, .star, .trash, .archive, .spam])
        #expect(picks.choices == [.star, .snooze, .trash], "each once, the first three")
        #expect(picks.isFull)
        #expect(picks.adding(.archive) == picks, "a fourth doesn't fit")
        #expect(picks.removing(.snooze).adding(.archive).choices == [.star, .trash, .archive], "added last")
        #expect(picks.unpicked == [.read, .archive, .spam])
    }

    @Test func movingAPickPutsItWhereItWasDropped() {
        let picks = HoverActions.Picks([.archive, .trash, .read])
        #expect(picks.moving(from: [2], to: 0).choices == [.read, .archive, .trash])
        #expect(picks.moving(from: [0], to: 3).choices == [.trash, .read, .archive])
    }

    @Test func offShowsNothing() {
        #expect(HoverActions.off.shown.isEmpty)
        #expect(choices(.off, thread(["INBOX"])).isEmpty)
    }

    @Test func aChoiceThatMeansNothingHereIsLeftOut() {
        let hover = HoverActions.on(HoverActions.Picks([.spam, .read, .snooze]))
        #expect(choices(hover, thread(["SPAM"]), in: .spam) == [.read])
    }

    @Test func buttonsDoWhatTheSwipesDo() {
        let buttons = HoverActions.standard.buttons(for: thread(["INBOX"]), at: .inbox, tints: .standard)
        #expect(buttons.map(\.swipe) == [.perform(.archive), .perform(.trash), .perform(.markRead(true))])
    }

    @Test func everyChoiceNamesTheCommandThatHoldsItsKeys() {
        let commands = SwipeChoice.allCases.map(\.command)
        #expect(commands == [.markRead, .star, .archive, .snooze, .trash, .reportSpam])
    }

    @Test func aTooltipNamesTheActionAndItsKeys() {
        #expect(HoverAction.Face.tooltip(title: "Archive", command: .archive) == "Archive ⌃⌘A")
        #expect(HoverAction.Face.tooltip(title: "Mark as Unread", command: .markRead) == "Mark as Unread ⇧⌘U")
        #expect(HoverAction.Face.tooltip(title: "Trash", command: .trash) == "Trash ⌘⌫")
    }

    @Test func aCommandWithoutKeysGivesJustTheName() {
        #expect(HoverAction.Face.tooltip(title: "Pin", command: .pin) == "Pin")
    }

    @Test func eachButtonLightsUpInItsActionsOwnColor() {
        for choice in SwipeChoice.allCases {
            #expect(HoverAction.Face(title: "", symbol: "", choice: choice).color == choice.color)
        }
    }
}
