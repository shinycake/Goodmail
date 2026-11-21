import Foundation
import MailCore
import Testing
import UIKit

@testable import MailUI

/// The list's pick in a window: a desktop one follows clicks and keys and moves on to the next row when rows leave,
/// which the reader follows; a touch one only hears what the collection view picked, and drops rows that leave.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ListPickTests {
    private let ids = (0..<4).map { ThreadSummary.ID(accountID: AccountID(rawValue: "a"), threadID: "t\($0)") }
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func threads(_ ids: [ThreadSummary.ID]) -> [ThreadSummary] {
        ids.enumerated().map { index, id in
            ThreadSummary(
                id: id, subject: "s", snippet: "", sender: Contact(name: nil, address: "x@example.com"),
                date: now - Double(index) * 60, isUnread: false, messageCount: 1, labelIDs: ["INBOX"])
        }
    }

    /// A list in a window driven by `interaction`, the stream that feeds it, and the routes it asks for.
    private func list(_ interaction: InteractionStyle) -> (
        MailboxViewModel, AsyncThrowingStream<[ThreadSummary], any Error>.Continuation, Routes
    ) {
        let (stream, feed) = AsyncThrowingStream<[ThreadSummary], any Error>.makeStream()
        let routes = Routes()
        let list = MailboxViewModel(
            accounts: [], source: .flat { stream }, refresh: {}, navigate: { routes.all.append($0) },
            interaction: interaction, now: { now })
        return (list, feed, routes)
    }

    private final class Routes {
        var all: [Route] = []
    }

    /// Hands the list `ids` and waits until it shows them.
    private func show(
        _ ids: [ThreadSummary.ID], in list: MailboxViewModel,
        through feed: AsyncThrowingStream<[ThreadSummary], any Error>.Continuation
    ) async {
        feed.yield(threads(ids))
        while list.rows != ids { await Task.yield() }
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

    @Test func deletingOnADesktopReadsTheNextRow() async {
        let (list, feed, routes) = list(.desktop)
        let observing = Task { await list.observe() }
        await show(ids, in: list, through: feed)
        list.click(ids[1], .plain)
        list.click(ids[2], .extend)
        await show([ids[0], ids[3]], in: list, through: feed)
        #expect(list.selection == .reading(ids[3]))
        #expect(routes.all.last == .thread(ids[3], in: .inbox))
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
        #expect(list.selection == .none, "the reader closes itself; the list doesn't move on")
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
