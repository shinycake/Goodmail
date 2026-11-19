import Foundation
import MailCore
import Testing

struct QuickActionTests {
    private let work = AccountID(rawValue: "work")
    private let home = AccountID(rawValue: "home")
    private var draft: ThreadSummary.ID { ThreadSummary.ID(accountID: work, threadID: "d1") }

    @Test func noAccountOffersNothing() {
        #expect(QuickAction.menu(accounts: [], newestDraft: nil).isEmpty)
    }

    @Test func oneAccountOffersWritingAndFinding() {
        #expect(QuickAction.menu(accounts: [work], newestDraft: nil) == [.newMessage, .search, .unread])
        #expect(
            QuickAction.menu(accounts: [work], newestDraft: draft) == [.newMessage, .search, .unread, .draft(draft)])
    }

    @Test func severalAccountsFillWhatIsLeftWithInboxesInTheirOrder() {
        #expect(
            QuickAction.menu(accounts: [home, work], newestDraft: nil) == [.newMessage, .search, .unread, .inbox(home)])
        // The draft waiting to be finished comes before any Inbox, and the Home Screen shows no more than four.
        #expect(
            QuickAction.menu(accounts: [home, work], newestDraft: draft) == [
                .newMessage, .search, .unread, .draft(draft),
            ])
    }

    @Test(arguments: [
        QuickAction.newMessage, .search, .unread,
        .draft(ThreadSummary.ID(accountID: AccountID(rawValue: "a"), threadID: "t")), .inbox(AccountID(rawValue: "a")),
    ])
    func readsBackWhatItOffered(action: QuickAction) throws {
        #expect(try QuickAction(encoded: action.encoded()) == action)
    }

    @Test func eachKindHasItsOwnType() {
        let types = [QuickAction.newMessage, .search, .unread, .draft(draft), .inbox(work)].map(\.type)
        #expect(Set(types).count == types.count)
    }

    @Test func somethingElseDoesNotRead() {
        #expect(throws: (any Error).self) { try QuickAction(encoded: Data("{\"later\":{}}".utf8)) }
    }
}
