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

    /// What `side` does for `thread`, leaving out the tints.
    private func swipes(_ arrangement: SwipeArrangement, _ thread: ThreadSummary, _ side: SwipeArrangement.Side)
        -> [MailboxViewModel.Swipe]
    {
        arrangement.buttons(for: thread, on: side, tints: .standard).map(\.swipe)
    }

    @Test func theStandardArrangementKeepsTheUsualSwipesInEveryMailbox() {
        let standard = SwipeArrangement.standard
        #expect(
            swipes(standard, thread(["INBOX"]), .leading) == [.perform(.markRead(true)), .perform(.star(true))])
        #expect(
            swipes(standard, thread(["INBOX"]), .trailing) == [.perform(.archive), .snooze, .perform(.trash)])
        #expect(swipes(standard, thread(["SPAM"]), .trailing) == [.perform(.moveToInbox), .perform(.trash)])
        #expect(
            swipes(standard, thread(["TRASH"]), .trailing) == [.perform(.untrash), .perform(.deleteForever)])
        #expect(swipes(standard, thread(["SENT"]), .trailing) == [.perform(.trash)])
    }

    @Test func choicesFollowTheThreadsState() {
        let arrangement = SwipeArrangement(leading: [.read, .star], trailing: [])
        let shown = swipes(arrangement, thread(["INBOX", "STARRED"], unread: false), .leading)
        #expect(shown == [.perform(.markRead(false)), .perform(.star(false))])
    }

    @Test func aChoiceThatMeansNothingHereIsLeftOut() {
        let arrangement = SwipeArrangement(leading: [.spam, .snooze], trailing: [])
        #expect(swipes(arrangement, thread(["SPAM"]), .leading).isEmpty)
        #expect(swipes(arrangement, thread(["INBOX"]), .leading) == [.perform(.reportSpam), .snooze])
    }

    @Test func eachChoiceSitsOnOneSideAtMostAndASideHoldsThree() {
        let arrangement = SwipeArrangement(leading: [.read, .star, .read, .trash, .spam], trailing: [.star, .archive])
        #expect(arrangement.leading == [.read, .star, .trash])
        #expect(arrangement.trailing == [.archive])
        #expect(arrangement.unused == [.snooze, .spam])
    }

    @Test func addingMovesAChoiceAcrossAndAFullSideRefuses() {
        var arrangement = SwipeArrangement.standard
        arrangement.add(.star, to: .trailing)
        #expect(arrangement.trailing == [.archive, .snooze, .trash])
        arrangement.remove(at: [1], from: .trailing)
        arrangement.add(.star, to: .trailing)
        #expect(arrangement.leading == [.read])
        #expect(arrangement.trailing == [.archive, .trash, .star])
    }

    @Test func reorderingPutsTheMovedChoiceFirst() {
        var arrangement = SwipeArrangement.standard
        arrangement.move(from: [2], to: 0, on: .trailing)
        #expect(arrangement.trailing == [.trash, .archive, .snooze])
        arrangement.move(from: [0], to: 3, on: .trailing)
        #expect(arrangement.trailing == [.archive, .snooze, .trash])
    }

    @Test func aSideCanBeEmptied() {
        var arrangement = SwipeArrangement.standard
        arrangement.remove(at: [0, 1], from: .leading)
        #expect(arrangement.leading.isEmpty)
        #expect(swipes(arrangement, thread(["INBOX"]), .leading).isEmpty)
    }

    @MainActor @Test func anEmptiedSideStaysEmptyOnceStored() {
        let saved = Preferences.swipeArrangement
        defer { Preferences.swipeArrangement = saved }
        Preferences.swipeArrangement = SwipeArrangement(leading: [], trailing: [.trash, .archive])
        #expect(Preferences.swipeArrangement == SwipeArrangement(leading: [], trailing: [.trash, .archive]))
    }
}
