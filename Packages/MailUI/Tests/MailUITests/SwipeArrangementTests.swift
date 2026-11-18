import Foundation
import MailCore
import Testing

@testable import MailUI

struct SwipeArrangementTests {
    private func thread(_ labels: Set<String>, unread: Bool = true) -> ThreadSummary {
        ThreadSummary(
            id: ThreadSummary.ID(accountID: AccountID(rawValue: "a"), threadID: "t"), subject: "", snippet: "",
            sender: Contact(name: nil, address: "x@example.com"), date: .now, isUnread: unread, messageCount: 1,
            labelIDs: labels)
    }

    /// What `side` does for `thread` listed in `mailbox`, leaving out the tints.
    private func swipes(
        _ arrangement: SwipeArrangement, _ thread: ThreadSummary, _ side: SwipeSide,
        in mailbox: Mailbox = .inbox
    ) -> [MailboxViewModel.Swipe] {
        arrangement.buttons(for: thread, at: ThreadPlace(thread, in: mailbox), on: side, tints: .standard)
            .map(\.swipe)
    }

    @Test func theStandardArrangementKeepsTheUsualSwipesInEveryMailbox() {
        let standard = SwipeArrangement.standard
        #expect(
            swipes(standard, thread(["INBOX"]), .left) == [.perform(.markRead(true)), .perform(.star(true))])
        #expect(
            swipes(standard, thread(["INBOX"]), .right) == [.perform(.archive), .snooze, .perform(.trash)])
        #expect(
            swipes(standard, thread(["SPAM"]), .right, in: .spam) == [.perform(.moveToInbox), .perform(.trash)])
        #expect(
            swipes(standard, thread(["TRASH"]), .right, in: .trash)
                == [.perform(.untrash), .perform(.deleteForever)])
        #expect(swipes(standard, thread(["SENT"]), .right, in: .sent) == [.perform(.trash)])
    }

    @Test func anInboxThreadWithTrashedMessagesSwipesAsAnInboxThread() {
        // A reply that came in to a trashed thread puts it back in the Inbox, still carrying Trash for the rest.
        let mixed = thread(["INBOX", "TRASH"])
        #expect(
            swipes(.standard, mixed, .right) == [.perform(.archive), .snooze, .perform(.trash)],
            "Delete Forever there would delete only the trashed messages, and the reply would come back")
        #expect(
            swipes(.standard, mixed, .right, in: .trash) == [.perform(.untrash), .perform(.deleteForever)],
            "in Trash it deletes forever")
    }

    @Test func choicesFollowTheThreadsState() {
        let arrangement = SwipeArrangement(left: [.read, .star], right: [])
        let shown = swipes(arrangement, thread(["INBOX", "STARRED"], unread: false), .left)
        #expect(shown == [.perform(.markRead(false)), .perform(.star(false))])
    }

    @Test func aChoiceThatMeansNothingHereIsLeftOut() {
        let arrangement = SwipeArrangement(left: [.spam, .snooze], right: [])
        #expect(swipes(arrangement, thread(["SPAM"]), .left, in: .spam).isEmpty)
        #expect(swipes(arrangement, thread(["INBOX"]), .left) == [.perform(.reportSpam), .snooze])
    }

    @Test func eachChoiceSitsOnOneSideAtMostAndASideHoldsThree() {
        let arrangement = SwipeArrangement(left: [.read, .star, .read, .trash, .spam], right: [.star, .archive])
        #expect(arrangement.left == [.read, .star, .trash])
        #expect(arrangement.right == [.archive])
        #expect(arrangement.unused == [.snooze, .spam])
    }

    @Test func addingMovesAChoiceAcrossAndAFullSideRefuses() {
        var arrangement = SwipeArrangement.standard
        arrangement.add(.star, to: .right)
        #expect(arrangement.right == [.archive, .snooze, .trash])
        arrangement.remove(at: [1], from: .right)
        arrangement.add(.star, to: .right)
        #expect(arrangement.left == [.read])
        #expect(arrangement.right == [.archive, .trash, .star])
    }

    @Test func reorderingPutsTheMovedChoiceFirst() {
        var arrangement = SwipeArrangement.standard
        arrangement.move(from: [2], to: 0, on: .right)
        #expect(arrangement.right == [.trash, .archive, .snooze])
        arrangement.move(from: [0], to: 3, on: .right)
        #expect(arrangement.right == [.archive, .snooze, .trash])
    }

    @Test func aSideCanBeEmptied() {
        var arrangement = SwipeArrangement.standard
        arrangement.remove(at: [0, 1], from: .left)
        #expect(arrangement.left.isEmpty)
        #expect(swipes(arrangement, thread(["INBOX"]), .left).isEmpty)
    }

    @MainActor @Test func anEmptiedSideStaysEmptyOnceStored() {
        let saved = Preferences.swipeArrangement
        defer { Preferences.swipeArrangement = saved }
        Preferences.swipeArrangement = SwipeArrangement(left: [], right: [.trash, .archive])
        #expect(Preferences.swipeArrangement == SwipeArrangement(left: [], right: [.trash, .archive]))
    }
}
