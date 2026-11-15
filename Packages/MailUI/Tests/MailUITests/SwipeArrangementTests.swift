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

    @Test func theStandardArrangementKeepsTheUsualSwipesInEveryMailbox() {
        let standard = SwipeArrangement.standard
        #expect(
            standard.swipes(for: thread(["INBOX"]), on: .leading) == [.perform(.markRead(true)), .perform(.star(true))])
        #expect(
            standard.swipes(for: thread(["INBOX"]), on: .trailing) == [.perform(.archive), .snooze, .perform(.trash)])
        #expect(standard.swipes(for: thread(["SPAM"]), on: .trailing) == [.perform(.moveToInbox), .perform(.trash)])
        #expect(
            standard.swipes(for: thread(["TRASH"]), on: .trailing) == [.perform(.untrash), .perform(.deleteForever)])
        #expect(standard.swipes(for: thread(["SENT"]), on: .trailing) == [.perform(.trash)])
    }

    @Test func choicesFollowTheThreadsState() {
        let arrangement = SwipeArrangement(leading: [.read, .star], trailing: [])
        let swipes = arrangement.swipes(for: thread(["INBOX", "STARRED"], unread: false), on: .leading)
        #expect(swipes == [.perform(.markRead(false)), .perform(.star(false))])
    }

    @Test func aChoiceThatMeansNothingHereIsLeftOut() {
        let arrangement = SwipeArrangement(leading: [.spam, .snooze], trailing: [])
        #expect(arrangement.swipes(for: thread(["SPAM"]), on: .leading).isEmpty)
        #expect(arrangement.swipes(for: thread(["INBOX"]), on: .leading) == [.perform(.reportSpam), .snooze])
    }

    @Test func eachChoiceSitsOnOneSideAtMostAndASideHoldsThree() {
        let arrangement = SwipeArrangement(leading: [.read, .star, .read, .trash, .spam], trailing: [.star, .archive])
        #expect(arrangement.leading == [.read, .star, .trash])
        #expect(arrangement.trailing == [.archive])
        #expect(arrangement.unused == [.snooze, .spam])
    }

    @Test func addingPutsAChoiceLastAndAFullSideRefuses() {
        var arrangement = SwipeArrangement.standard
        arrangement.move([.spam], to: .side(.trailing))
        #expect(arrangement == .standard)
        arrangement.move([.spam], to: .side(.leading))
        #expect(arrangement.leading == [.read, .star, .spam])
        #expect(arrangement.unused == [])
    }

    @Test func draggingAcrossTakesTheChoiceOffItsOldSide() {
        var arrangement = SwipeArrangement.standard
        arrangement.move([.trash], to: .side(.leading), before: .read)
        #expect(arrangement.leading == [.trash, .read, .star])
        #expect(arrangement.trailing == [.archive, .snooze])
    }

    @Test func draggingOntoAFullSideChangesNothing() {
        var arrangement = SwipeArrangement.standard
        arrangement.move([.star], to: .side(.trailing), before: .archive)
        #expect(arrangement == .standard)
    }

    @Test func draggingToMoreActionsTakesTheChoiceOffItsSide() {
        var arrangement = SwipeArrangement.standard
        arrangement.move([.snooze], to: .unused, before: .spam)
        #expect(arrangement.trailing == [.archive, .trash])
        #expect(arrangement.unused == [.snooze, .spam])
    }

    @Test(arguments: [
        (SwipeChoice.trash, SwipeChoice?.some(.archive), [SwipeChoice.trash, .archive, .snooze]),
        (.archive, nil, [.snooze, .trash, .archive]),
        (.snooze, .snooze, [.archive, .snooze, .trash]),
    ])
    func reorderingWithinASide(moving choice: SwipeChoice, before anchor: SwipeChoice?, expected: [SwipeChoice]) {
        var arrangement = SwipeArrangement.standard
        arrangement.move([choice], to: .side(.trailing), before: anchor)
        #expect(arrangement.trailing == expected)
    }

    @Test func severalChoicesMoveTogetherInTheirOrder() {
        var arrangement = SwipeArrangement(leading: [.read], trailing: [.archive, .snooze, .trash])
        arrangement.move([.snooze, .trash], to: .side(.leading), before: .read)
        #expect(arrangement.leading == [.snooze, .trash, .read])
        #expect(arrangement.trailing == [.archive])
    }

    @Test func aSideCanBeEmptied() {
        var arrangement = SwipeArrangement.standard
        arrangement.move(arrangement.leading, to: .unused)
        #expect(arrangement.leading.isEmpty)
        #expect(arrangement.swipes(for: thread(["INBOX"]), on: .leading).isEmpty)
    }

    @MainActor @Test func anEmptiedSideStaysEmptyOnceStored() {
        let saved = Preferences.swipeArrangement
        defer { Preferences.swipeArrangement = saved }
        Preferences.swipeArrangement = SwipeArrangement(leading: [], trailing: [.trash, .archive])
        #expect(Preferences.swipeArrangement == SwipeArrangement(leading: [], trailing: [.trash, .archive]))
    }
}
