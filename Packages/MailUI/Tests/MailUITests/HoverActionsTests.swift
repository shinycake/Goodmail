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

    private func choices(
        _ arrangement: SwipeArrangement, _ thread: ThreadSummary, in mailbox: Mailbox = .inbox
    ) -> [SwipeChoice] {
        arrangement.hoverButtons(for: thread, at: ThreadPlace(thread, in: mailbox), tints: .standard).map(\.choice)
    }

    @Test func theStandardArrangementShowsTheLeftSideThenTheRightSideInTheirOrder() {
        #expect(choices(.standard, thread(["INBOX"])) == [.read, .star, .archive, .snooze, .trash])
    }

    @Test func aChosenArrangementKeepsItsOrderOnEachSide() {
        let arrangement = SwipeArrangement(left: [.star], right: [.trash, .archive])
        #expect(choices(arrangement, thread(["INBOX"])) == [.star, .trash, .archive])
    }

    @Test func aChoiceThatMeansNothingHereIsLeftOut() {
        let arrangement = SwipeArrangement(left: [.spam, .read], right: [.snooze])
        #expect(choices(arrangement, thread(["SPAM"]), in: .spam) == [.read])
    }

    @Test func buttonsDoWhatTheSwipesDo() {
        let buttons = SwipeArrangement.standard.hoverButtons(
            for: thread(["INBOX"]), at: .inbox, tints: .standard)
        #expect(
            buttons.map(\.swipe)
                == [.perform(.markRead(true)), .perform(.star(true)), .perform(.archive), .snooze, .perform(.trash)])
    }

    @Test func aSideWithNoChoicesLeavesOnlyTheOther() {
        #expect(choices(SwipeArrangement(left: [], right: [.archive]), thread(["INBOX"])) == [.archive])
        #expect(choices(SwipeArrangement(left: [], right: []), thread(["INBOX"])).isEmpty)
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

    @Test func onlyTrashWearsRed() {
        let faces = SwipeChoice.allCases.map { HoverAction.Face(title: "", symbol: "", choice: $0).isDestructive }
        #expect(faces == [false, false, false, false, true, false])
    }
}
