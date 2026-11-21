import Foundation
import MailCore
import Testing

@testable import MailUI

/// The window says which row is read (`markReading`), and the list holds it at once, listed or not, so the filter
/// keeps it and a row that comes back shows as read (R11).
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ReadRowTests {
    private let account = Account(id: AccountID(rawValue: "a"), email: "a@example.com", color: .teal, service: .gmail)
    private var ids: [ThreadSummary.ID] { (0..<4).map { ThreadSummary.ID(accountID: account.id, threadID: "t\($0)") } }
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func threads(_ ids: [ThreadSummary.ID], unread: Set<ThreadSummary.ID>) -> [ThreadSummary] {
        ids.map { id in
            ThreadSummary(
                id: id, subject: "s", snippet: "", sender: Contact(name: nil, address: "x@example.com"),
                date: now - Double(self.ids.firstIndex(of: id) ?? 0) * 60, isUnread: unread.contains(id),
                messageCount: 1, labelIDs: ["INBOX"])
        }
    }

    private func list(_ interaction: InteractionStyle) -> (
        MailboxViewModel, AsyncThrowingStream<[ThreadSummary], any Error>.Continuation
    ) {
        let (stream, feed) = AsyncThrowingStream<[ThreadSummary], any Error>.makeStream()
        let list = MailboxViewModel(
            accounts: [account], source: .flat { stream }, filter: .on([.unread]), didChangeFilter: { _ in },
            refresh: {}, interaction: interaction, now: { now })
        return (list, feed)
    }

    @Test(arguments: [InteractionStyle.desktop, .touch])
    func undoUnderTheUnreadFilterListsTheRowAgainAndMovesThePick(interaction: InteractionStyle) async {
        let (list, feed) = list(interaction)
        let observing = Task { await list.observe() }
        let (t0, t1, t2, t3) = (ids[0], ids[1], ids[2], ids[3])
        feed.yield(threads(ids, unread: Set(ids)))
        while list.rows != ids { await Task.yield() }

        // t1 was read, then archived; the window went on to t2, which opening read.
        list.markReading(t1)
        list.markReading(t2)
        feed.yield(threads([t0, t2, t3], unread: [t0, t3]))
        while list.rows != [t0, t2, t3] { await Task.yield() }

        // Undo: the window reads t1 again before the store brings it back.
        list.markReading(t1)
        #expect(list.selection == .reading(t1), "the pick moves at once, listed or not")
        #expect(list.rows == [t0, t3], "t2, read and no longer open, leaves")
        feed.yield(threads(ids, unread: [t0, t3]))
        while list.rows != [t0, t1, t3] { await Task.yield() }
        #expect(list.selection == .reading(t1), "its row is back, and shows as read")
        feed.finish()
        await observing.value
    }

    @Test func markingNoneLeavesSeveralPicked() async {
        let (list, feed) = list(.desktop)
        let observing = Task { await list.observe() }
        feed.yield(threads(ids, unread: Set(ids)))
        while list.rows != ids { await Task.yield() }
        list.click(ids[0], .plain)
        list.click(ids[2], .toggle)
        list.markReading(nil)
        #expect(list.selection == .several([ids[0], ids[2]], anchor: ids[2]))
        list.markReading(ids[3])
        list.markReading(nil)
        #expect(list.selection == .none)
        feed.finish()
        await observing.value
    }
}
