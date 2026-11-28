import Foundation
import MailCore
import Testing
import UIKit

@testable import MailUI

/// The list's pick in a window: a desktop one follows clicks and keys, which the reader follows; a touch one only hears
/// what the collection view picked. Either drops rows that leave and opens nothing for it: where the reader goes after
/// an action is the window's to say, and what sync takes away never moves it (R6).
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ListPickTests {
    private let account = Account(id: AccountID(rawValue: "a"), email: "a@example.com", color: .teal, service: .gmail)
    private var ids: [ThreadSummary.ID] { (0..<4).map { ThreadSummary.ID(accountID: account.id, threadID: "t\($0)") } }
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func threads(_ ids: [ThreadSummary.ID], unread: Set<ThreadSummary.ID> = []) -> [ThreadSummary] {
        ids.enumerated().map { index, id in
            ThreadSummary(
                id: id, subject: "s", snippet: "", sender: Contact(name: nil, address: "x@example.com"),
                date: now - Double(index) * 60, isUnread: unread.contains(id), messageCount: 1, labelIDs: ["INBOX"])
        }
    }

    /// A list in a window driven by `interaction`, the stream that feeds it, and the routes it asks for.
    private func list(_ interaction: InteractionStyle, filter: ListFilter = .none) -> (
        MailboxViewModel, AsyncThrowingStream<[ThreadSummary], any Error>.Continuation, Routes
    ) {
        let (stream, feed) = AsyncThrowingStream<[ThreadSummary], any Error>.makeStream()
        let routes = Routes()
        let list = MailboxViewModel(
            accounts: [account], source: .flat(.whole { stream }), filter: filter, didChangeFilter: { _ in },
            refresh: {},
            navigate: { routes.all.append($0) }, interaction: interaction, now: { now })
        return (list, feed, routes)
    }

    private final class Routes {
        var all: [Route] = []
    }

    /// Hands the list `ids` and waits until it shows `shown`, all of them unless a filter hides some.
    private func show(
        _ ids: [ThreadSummary.ID], unread: Set<ThreadSummary.ID> = [], in list: MailboxViewModel,
        through feed: AsyncThrowingStream<[ThreadSummary], any Error>.Continuation,
        showing shown: [ThreadSummary.ID]? = nil
    ) async {
        feed.yield(threads(ids, unread: unread))
        while list.rows != shown ?? ids { await Task.yield() }
    }

    @Test func aDesktopPickOpensWhatItReadsAndCountsSeveral() async {
        let (list, feed, routes) = list(.desktop)
        let observing = Task { await list.observe() }
        await show(ids, in: list, through: feed)
        list.click(ids[1], .plain)
        list.click(ids[2], .toggle)
        list.dropSelection()
        #expect(list.selection == .reading(ids[2]))
        #expect(
            routes.all == [.thread(ids[1], in: .inbox), .selection(count: 2), .thread(ids[2], in: .inbox)])
        feed.finish()
        await observing.value
    }

    @Test func aRowTakenAwayOnADesktopLeavesThePickAndOpensNothing() async {
        let (list, feed, routes) = list(.desktop)
        let observing = Task { await list.observe() }
        await show(ids, in: list, through: feed)
        list.click(ids[1], .plain)
        await show([ids[1], ids[2], ids[3]], in: list, through: feed)
        #expect(list.selection == .reading(ids[1]), "another row leaving keeps the one read")
        await show([ids[2], ids[3]], in: list, through: feed)
        #expect(list.selection == .reading(ids[1]), "its own row leaving opens nothing in its place: it is still read")
        #expect(routes.all == [.thread(ids[1], in: .inbox)])
        feed.finish()
        await observing.value
    }

    @Test func severalOnADesktopCountWhatIsLeftOfThem() async {
        let (list, feed, routes) = list(.desktop)
        let observing = Task { await list.observe() }
        await show(ids, in: list, through: feed)
        list.click(ids[0], .plain)
        list.click(ids[2], .extend)
        await show([ids[0], ids[1], ids[3]], in: list, through: feed)
        #expect(list.selection == .several([ids[0], ids[1]], anchor: ids[0]))
        await show([ids[3]], in: list, through: feed)
        #expect(list.selection == .none)
        #expect(
            routes.all == [
                .thread(ids[0], in: .inbox), .selection(count: 3), .selection(count: 2), .selection(count: 0),
            ])
        feed.finish()
        await observing.value
    }

    @Test func undoPicksTheRowsAgainOnceTheyAreBack() async {
        let (list, feed, routes) = list(.desktop)
        let observing = Task { await list.observe() }
        // The pick was trashed: its rows left, and the list went on to the next.
        await show([ids[2], ids[3]], in: list, through: feed)
        list.click(ids[2], .plain)
        list.repick([ids[0], ids[1]])
        #expect(list.selection == .several([ids[0], ids[1]], anchor: ids[0]), "at once, before the rows come back")
        await show([ids[1], ids[2], ids[3]], in: list, through: feed)
        #expect(list.selection == .several([ids[0], ids[1]], anchor: ids[0]), "waits for the row not back yet")
        await show(ids, in: list, through: feed)
        await show([ids[0], ids[2], ids[3]], in: list, through: feed)
        #expect(list.selection == .several([ids[0]], anchor: ids[0]), "once back, a row that leaves again drops out")
        #expect(routes.all == [.thread(ids[2], in: .inbox), .selection(count: 2), .selection(count: 1)])
        feed.finish()
        await observing.value
    }

    @Test func anotherPickEndsTheWaitForUndosRows() async {
        let (list, feed, _) = list(.desktop)
        let observing = Task { await list.observe() }
        await show([ids[2], ids[3]], in: list, through: feed)
        list.repick([ids[0], ids[1]])
        list.click(ids[3], .plain)
        await show(ids, in: list, through: feed)
        #expect(list.selection == .reading(ids[3]))
        list.click(ids[2], .toggle)
        await show([ids[2], ids[3]], in: list, through: feed)
        #expect(list.selection == .several([ids[2], ids[3]], anchor: ids[2]))
        feed.finish()
        await observing.value
    }

    @Test(arguments: [InteractionStyle.desktop, .touch])
    func theRowBeingReadStaysUnderTheUnreadFilterWhileItIsRead(interaction: InteractionStyle) async {
        let (list, feed, _) = list(interaction, filter: .on([.unread]))
        let observing = Task { await list.observe() }
        func read(_ id: ThreadSummary.ID) {
            switch interaction {
            case .desktop: list.click(id, .plain)
            case .touch: list.picked([id], selecting: false)
            }
        }
        await show(ids, unread: Set(ids), in: list, through: feed)
        read(ids[1])
        // Opening it read it.
        await show(ids, unread: [ids[0], ids[2], ids[3]], in: list, through: feed)
        #expect(list.selection == .reading(ids[1]), "it reads on, and the next isn't opened and read in turn")
        read(ids[2])
        await show(ids, unread: [ids[0], ids[3]], in: list, through: feed)
        #expect(list.selection == .reading(ids[2]))
        #expect(list.hiddenByFilter == 0, "the one read before stays for the visit, so Previous goes back to it")
        feed.finish()
        await observing.value
    }

    @Test func touchOnlyDropsRowsThatLeaveAndOpensNothing() async {
        let (list, feed, routes) = list(.touch)
        let observing = Task { await list.observe() }
        await show(ids, in: list, through: feed)
        list.picked([ids[1], ids[2]], selecting: true)
        await show([ids[0], ids[2], ids[3]], in: list, through: feed)
        #expect(list.selection == .several([ids[2]], anchor: nil))
        list.picked([ids[1]], selecting: false)
        await show([ids[0], ids[3]], in: list, through: feed)
        #expect(list.selection == .reading(ids[1]), "the window moves the reader; the list doesn't move on")
        #expect(routes.all.isEmpty)
        feed.finish()
        await observing.value
    }

    @Test func aMenuOnAPickedRowIsForTheWholePick() async {
        let (list, feed, _) = list(.desktop)
        let observing = Task { await list.observe() }
        await show(ids, in: list, through: feed)
        list.click(ids[2], .plain)
        list.click(ids[0], .toggle)
        #expect(list.menuTargets(for: ids[2]) == [ids[0], ids[2]])
        #expect(list.menuTargets(for: ids[3]) == [ids[3]])
        feed.finish()
        await observing.value
    }

    @Test func modifierKeysChooseTheClick() {
        #expect(RowClicks.click(with: []) == .plain)
        #expect(RowClicks.click(with: .command) == .toggle)
        #expect(RowClicks.click(with: .shift) == .extend)
        #expect(RowClicks.click(with: [.command, .shift]) == .extend, "⇧ wins, as in Finder")
        #expect(RowClicks.click(with: .alternate) == .plain)
    }

    @Test func severalThreadsGetTheMenuAllOfThemAllow() {
        let inbox = threads([ids[0]])[0]
        var archived = threads([ids[1]])[0]
        archived.labelIDs = [SystemLabel.starred]
        let menu = ThreadMenu(several: [inbox, archived], in: .allMail, pin: true, opensWindows: true)
        #expect(
            menu.sections == [
                [.answer(.reply), .answer(.replyAll), .answer(.forward)],
                [.openInNewWindow],
                [.perform(.markRead(false)), .perform(.star(true)), .pin(true), .perform(.mute)],
                [.move, .changeLabels],
                [.perform(.reportSpam), .perform(.trash)],
            ])
    }

    @Test func anAssistivePressOnADesktopRowPicksItAsAClickDoes() async throws {
        let (list, feed, routes) = list(.desktop)
        let controller = MailboxViewController(viewModel: list)
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 400, height: 800)
        await show(ids, in: list, through: feed)
        // Out of a window UIKit doesn't run the update that shows the rows; run it as it would.
        controller.updateProperties()
        let collectionView = try #require(controller.collectionView)
        var row: ThreadRowContentView?
        while row == nil {
            collectionView.layoutIfNeeded()
            row = collectionView.cellForItem(at: IndexPath(item: 1, section: 0))?.contentView as? ThreadRowContentView
            if row == nil { await Task.yield() }
        }
        #expect(try #require(row).accessibilityActivate())
        #expect(list.selection == .reading(ids[1]))
        #expect(routes.all.last == .thread(ids[1], in: .inbox))
        feed.finish()
    }
}
