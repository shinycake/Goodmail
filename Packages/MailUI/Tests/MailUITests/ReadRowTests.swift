import Foundation
import MailCore
import Testing

@testable import MailUI

/// The window says which row is read (`markReading`), and the list holds it at once, listed or not, so the filter
/// keeps it for the rest of the visit and a row that comes back shows as read (R11).
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

    private func list(_ interaction: InteractionStyle, filter: ListFilter = .on([.unread])) -> (
        MailboxViewModel, AsyncThrowingStream<[ThreadSummary], any Error>.Continuation
    ) {
        let (stream, feed) = AsyncThrowingStream<[ThreadSummary], any Error>.makeStream()
        let list = MailboxViewModel(
            accounts: [account], source: .flat { stream }, filter: filter, didChangeFilter: { _ in },
            refresh: {}, actions: MailActions(commands: MailCommands(store: NoStore(), replay: { _ in })),
            interaction: interaction, now: { now })
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
        #expect(list.rows == [t0, t2, t3], "t2, read on this visit, stays listed, as in Mail")
        feed.yield(threads(ids, unread: [t0, t3]))
        while list.rows != ids { await Task.yield() }
        #expect(list.selection == .reading(t1), "its row is back, and shows as read")
        feed.finish()
        await observing.value
    }

    @Test func downFromAClickedRowThatLeftTheUnreadBoxReadsTheRowBelow() async {
        let (list, feed) = list(.desktop, filter: .none)
        let observing = Task { await list.observe() }
        feed.yield(threads(ids, unread: Set(ids)))
        while list.rows != ids { await Task.yield() }
        list.click(ids[1], .plain)
        // An Unread smart mailbox lists only unread mail, so the row leaves once it is read.
        feed.yield(threads([ids[0], ids[2], ids[3]], unread: [ids[0], ids[2], ids[3]]))
        while list.rows.count != 3 { await Task.yield() }
        list.move(1, extending: false)
        #expect(list.selection == .reading(ids[2]), "the row below, not the top")
        feed.finish()
        await observing.value
    }

    @Test func aConversationReadAgainOnceItsRowLeftMovesFromTheTop() async {
        let (list, feed) = list(.desktop, filter: .none)
        let observing = Task { await list.observe() }
        feed.yield(threads(ids, unread: []))
        while list.rows != ids { await Task.yield() }
        list.click(ids[1], .plain)
        // Another conversation, not listed here, is read; then t1's row goes.
        list.markReading(ThreadSummary.ID(accountID: account.id, threadID: "elsewhere"))
        feed.yield(threads([ids[0], ids[2], ids[3]], unread: []))
        while list.rows.count != 3 { await Task.yield() }
        // The window goes back to t1, whose row has left: it wasn't picked from these rows this time.
        list.markReading(ids[1])
        list.move(1, extending: false)
        #expect(list.selection == .reading(ids[0]), "no trail from when it was last picked")
        feed.finish()
        await observing.value
    }

    @Test func aPickKeepsItsTrailOnlyWhilePickedFromTheRows() {
        let rows = Array(ids.prefix(3))
        var pick = ListPick()
        pick.pick(.reading(ids[1]), from: rows)
        #expect(pick.trail == rows)
        pick.pick(.reading(ids[1]), from: [ids[0]])
        #expect(pick.trail == rows, "the same pick again keeps it")
        pick.pick(.reading(ids[3]), from: rows)
        #expect(pick.trail.isEmpty, "picked while not listed")
        pick.pick(.several([ids[0], ids[1]], anchor: ids[0]), from: rows)
        #expect(pick.trail.isEmpty)
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

    @Test func deleteAndReturnLeaveAConversationWhoseRowLeftToTheReader() async {
        let (list, feed) = list(.desktop, filter: .none)
        let observing = Task { await list.observe() }
        feed.yield(threads(ids, unread: []))
        while list.rows != ids { await Task.yield() }
        list.click(ids[1], .plain)
        #expect(list.answers(.delete, opensWindows: true))
        #expect(list.answers(.openWindow, opensWindows: true))
        // Archived on another device: the reader stays on it, and its row goes.
        feed.yield(threads([ids[0], ids[2], ids[3]], unread: []))
        while list.rows.count != 3 { await Task.yield() }
        #expect(list.selection == .reading(ids[1]))
        #expect(!list.answers(.delete, opensWindows: true), "Delete goes on to the reader's Trash")
        #expect(!list.answers(.openWindow, opensWindows: true))
        #expect(list.answers(.down, opensWindows: true))
        feed.finish()
        await observing.value
    }
}
