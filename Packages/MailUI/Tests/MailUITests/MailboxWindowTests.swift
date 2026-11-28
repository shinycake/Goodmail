import Foundation
import MailCore
import Testing

@testable import MailUI

/// A long mailbox's list reads a window of it (ADR-045): more as the reader nears the end, the service's older pages
/// only once the store has listed all it holds, and every thread for a filter, Select All and Empty Trash.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct MailboxWindowTests {
    private let account = Account(id: AccountID(rawValue: "a"), email: "a@example.com", color: .teal, service: .gmail)
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func thread(_ index: Int, labels: Set<String> = [SystemLabel.inbox], unread: Bool = true) -> ThreadSummary {
        ThreadSummary(
            id: ThreadSummary.ID(accountID: account.id, threadID: "t\(index)"), subject: "s", snippet: "",
            sender: Contact(name: nil, address: "x@example.com"), date: now - Double(index) * 60, isUnread: unread,
            messageCount: 1, labelIDs: labels)
    }

    /// A store holding `threads`, newest first, that lists each window as MailStore does and keeps what was asked.
    private final class Store {
        var threads: [ThreadSummary]
        /// The pinned and woken threads, which a window that doesn't reach them holds.
        var leading: Set<ThreadSummary.ID> = []
        /// Whether the whole mailbox is listed only on `answerWhole()`, as a slow read would.
        var waitsForWhole = false
        private(set) var asked: [ThreadWindow] = []
        private var unanswered: [AsyncThrowingStream<ThreadListing, any Error>.Continuation] = []

        init(_ threads: [ThreadSummary]) {
            self.threads = threads
        }

        func listings(_ window: ThreadWindow) -> AsyncThrowingStream<ThreadListing, any Error> {
            asked.append(window)
            let listing: ThreadListing
            if let limit = window.limit, threads.count > limit {
                let shown = Array(threads.prefix(limit))
                let held = threads.dropFirst(limit).filter { leading.contains($0.id) }
                listing = ThreadListing(threads: shown, held: held, reach: .more)
            } else {
                listing = ThreadListing(whole: threads)
            }
            let (stream, answer) = AsyncThrowingStream<ThreadListing, any Error>.makeStream()
            if window == .whole, waitsForWhole { unanswered.append(answer) } else { answer.yield(listing) }
            return stream
        }

        func answerWhole() {
            for answer in unanswered { answer.yield(ThreadListing(whole: threads)) }
            unanswered = []
        }
    }

    private final class Pages {
        var fetched = 0
    }

    private func list(
        _ store: Store, pages: Pages = Pages(), interaction: InteractionStyle = .touch, mailbox: Mailbox = .inbox
    ) -> MailboxViewModel {
        MailboxViewModel(
            mailbox: mailbox, accounts: [account], source: .flat(.windowed { store.listings($0) }),
            didChangeFilter: { _ in }, refresh: {},
            older: .pages {
                pages.fetched += 1
                return true
            },
            interaction: interaction, now: { [now] in now })
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<1_000 where !condition() { await Task.yield() }
        #expect(condition())
    }

    @Test func aLongMailboxOpensOnItsNewestThreads() async {
        let store = Store((0..<500).map { thread($0) })
        let list = list(store)
        let observing = Task { await list.observe() }
        defer { observing.cancel() }
        await waitUntil { list.rows.count == 200 }
        #expect(store.asked == [.newest(200)])
        #expect(list.listing.reach == .more)
    }

    @Test func nearTheEndTheListReadsTwiceAsManyAndOnlyThenTheServicesPages() async {
        let store = Store((0..<300).map { thread($0) })
        let pages = Pages()
        let list = list(store, pages: pages)
        let observing = Task { await list.observe() }
        defer { observing.cancel() }
        await waitUntil { list.rows.count == 200 }

        list.show(row: 150)
        #expect(store.asked == [.newest(200)], "far from the end")
        list.show(row: 190)
        list.show(row: 191)
        #expect(list.window.asked == .newest(400), "a second ask waits for the wider window's answer")
        await waitUntil { list.rows.count == 300 }
        #expect(store.asked == [.newest(200), .newest(400)])
        #expect(pages.fetched == 0, "the store held more, so the service wasn't asked")

        list.show(row: 290)
        await waitUntil { pages.fetched == 1 }
        #expect(store.asked == [.newest(200), .newest(400)], "the store has listed all it holds")
    }

    @Test func readingNearTheEndReadsFurther() async {
        let store = Store((0..<300).map { thread($0) })
        let list = list(store)
        let observing = Task { await list.observe() }
        defer { observing.cancel() }
        await waitUntil { list.rows.count == 200 }
        // Next Conversation, in a window that shows the reader and not the list.
        list.markReading(thread(195).id)
        #expect(list.window.asked == .newest(400))
        await waitUntil { list.rows.count == 300 }
    }

    @Test func aShortWindowedListAsksTheServiceOnlyWhenItIsWhole() async {
        let store = Store((0..<10).map { thread($0) })
        let pages = Pages()
        let list = list(store, pages: pages)
        let observing = Task { await list.observe() }
        defer { observing.cancel() }
        await waitUntil { pages.fetched == 1 }
        #expect(list.listing.reach == .whole)
    }

    @Test func aFilterReadsEveryThreadAndLetsGoWhenItIsOff() async {
        let store = Store((0..<300).map { thread($0) })
        let list = list(store)
        let observing = Task { await list.observe() }
        defer { observing.cancel() }
        await waitUntil { list.rows.count == 200 }

        list.setFilter(.on([.unread]))
        await waitUntil { list.rows.count == 300 }
        #expect(store.asked.last == .whole)
        list.setFilter(.none)
        await waitUntil { store.asked.last == .newest(200) }
        await waitUntil { list.rows.count == 200 }
    }

    @Test func selectAllPicksEveryThreadAndLetsGoWhenThePickEnds() async {
        let store = Store((0..<300).map { thread($0) })
        let list = list(store, interaction: .desktop)
        let observing = Task { await list.observe() }
        defer { observing.cancel() }
        await waitUntil { list.rows.count == 200 }

        #expect(await list.listEveryThreadToSelect())
        list.selectAll()
        #expect(list.selectedIDs.count == 300)
        list.click(thread(3).id, .plain)
        await waitUntil { store.asked.last == .newest(200) }
        await waitUntil { list.rows.count == 200 }
    }

    @Test func selectAllGivesUpWhenThePickEndsFirst() async {
        let store = Store((0..<300).map { thread($0) })
        let list = list(store, interaction: .desktop)
        let observing = Task { await list.observe() }
        defer { observing.cancel() }
        await waitUntil { list.rows.count == 200 }
        // Nothing but the list itself answers, so the click lands before the whole mailbox does.
        observing.cancel()
        await observing.value

        let waiting = Task { await list.listEveryThreadToSelect() }
        await waitUntil { list.window.isWhole(for: .selectAll) }
        list.click(thread(3).id, .plain)
        #expect(await waiting.value == false)
        #expect(list.window.asked == .newest(200))
    }

    @Test func turningAFilterOffKeepsTheConversationReadUnderItFarDownTheMailbox() async {
        // One in a hundred unread, so the filter's row 10 is the mailbox's thread 1,000.
        let store = Store((0..<3_000).map { thread($0, unread: $0 % 100 == 0) })
        let list = list(store)
        let observing = Task { await list.observe() }
        defer { observing.cancel() }
        await waitUntil { list.rows.count == 200 }
        list.setFilter(.on([.unread]))
        await waitUntil { list.rows.count == 30 }

        list.markReading(thread(1_000).id)
        list.setFilter(.none)
        #expect(list.window.asked == .newest(1_600), "deep enough for thread 1,000, not for the filter's row 10")
        await waitUntil { list.rows.count == 1_600 }
        #expect(list.reading == thread(1_000).id)
    }

    @Test func endingSelectAllAfterADeepScrollKeepsTheRowsReached() async {
        let store = Store((0..<3_000).map { thread($0) })
        let list = list(store, interaction: .desktop)
        let observing = Task { await list.observe() }
        defer { observing.cancel() }
        await waitUntil { list.rows.count == 200 }
        #expect(await list.listEveryThreadToSelect())
        list.selectAll()

        list.show(row: 1_000)
        list.click(thread(5).id, .plain)
        #expect(list.window.asked == .newest(1_600))
    }

    @Test func deselectingAllInSelectModeLetsTheWholeMailboxGo() async {
        let store = Store((0..<300).map { thread($0) })
        let list = list(store)
        let observing = Task { await list.observe() }
        defer { observing.cancel() }
        await waitUntil { list.rows.count == 200 }
        #expect(await list.listEveryThreadToSelect())
        list.picked(list.rows, selecting: true)
        #expect(list.window.asked == .whole)

        list.picked([], selecting: true)
        #expect(list.window.asked == .newest(200), "still selecting, but nothing needs every thread")
    }

    @Test func aCancelledSelectAllLetsTheWholeMailboxGo() async {
        let store = Store((0..<300).map { thread($0) })
        let list = list(store)
        let observing = Task { await list.observe() }
        await waitUntil { list.rows.count == 200 }
        // Nothing answers now, so the wait is still on when it is cancelled.
        observing.cancel()
        await observing.value

        let waiting = Task { await list.listEveryThreadToSelect() }
        await waitUntil { list.window.holds(.selectAll) }
        waiting.cancel()
        #expect(await waiting.value == false)
        #expect(list.window.asked == .newest(200))
    }

    @Test func emptyTrashTappedTwiceEmptiesItOnce() async {
        let store = Store((0..<300).map { thread($0, labels: [SystemLabel.trash]) })
        let list = list(store, mailbox: .trash)
        let observing = Task { await list.observe() }
        defer { observing.cancel() }
        await waitUntil { list.rows.count == 200 }
        let controller = MailboxViewController(viewModel: list)
        final class Found {
            var counts: [Int?] = []
        }
        let found = Found()
        store.waitsForWhole = true

        controller.whenEveryThread { found.counts.append(await $0.everyThread()?.count) }
        await waitUntil { list.window.holds(.everyThread) }
        controller.whenEveryThread { found.counts.append(await $0.everyThread()?.count) }
        await waitUntil { store.asked.filter { $0 == .whole }.count == 2 }
        store.answerWhole()
        await controller.everyThreadWait?.value
        #expect(found.counts == [nil, 300], "the first gives way, and its letting go leaves the second whole")
    }

    @Test func emptyTrashDeletesEveryThreadNotOnlyTheWindows() async {
        let store = Store((0..<300).map { thread($0, labels: [SystemLabel.trash]) })
        let list = list(store, mailbox: .trash)
        let observing = Task { await list.observe() }
        defer { observing.cancel() }
        await waitUntil { list.rows.count == 200 }

        let every = await list.everyThread()
        #expect(every?.count == 300)
        #expect(list.window.asked == .newest(200), "back to the window once they are in hand")
        await waitUntil { list.rows.count == 200 }
        #expect(!list.showsEvery(list.rows), "the window's rows are not all of Trash")
    }

    @Test func pinnedThreadsBelowTheWindowLeadTheListWhilePinned() async {
        let store = Store((0..<300).map { thread($0) })
        let old = thread(250)
        store.leading = [old.id]
        let (pins, pinning) = AsyncThrowingStream<Set<ThreadSummary.ID>, any Error>.makeStream()
        let list = MailboxViewModel(
            accounts: [account], source: .flat(.windowed { store.listings($0) }), pins: { pins }, refresh: {},
            now: { [now] in now })
        let observing = Task { await list.observe() }
        defer { observing.cancel() }

        pinning.yield([old.id])
        await waitUntil { list.sections.first?.id == .pinned }
        #expect(list.sections.first?.threads == [old])
        #expect(list.rows.count == 201)
        pinning.yield([])
        await waitUntil { list.rows.count == 200 }
        #expect(!list.rows.contains(old.id), "an unpinned thread below the window isn't in its time sections")
    }

    @Test func anotherCategoryStartsOnItsFirstWindow() async {
        var asked: [InboxCategory: [ThreadWindow]] = [:]
        let threads = (0..<300).map { thread($0) }
        let list = MailboxViewModel(
            accounts: [account],
            source: .categorised(
                InboxCategories(
                    threads: { category, window in
                        asked[category, default: []].append(window)
                        let limit = window.limit ?? threads.count
                        return AsyncThrowingStream {
                            $0.yield(
                                ThreadListing(
                                    threads: Array(threads.prefix(limit)),
                                    reach: limit < threads.count ? .more : .whole))
                        }
                    },
                    unreadCounts: { AsyncThrowingStream { $0.yield([:]) } }),
                selected: .primary),
            refresh: {})
        let observing = Task { await list.observe() }
        defer { observing.cancel() }
        await waitUntil { list.rows.count == 200 }
        list.show(row: 190)
        await waitUntil { list.rows.count == 300 }

        list.select(.social)
        await waitUntil { asked[.social] != nil }
        #expect(asked[.primary] == [.newest(200), .newest(400)])
        #expect(asked[.social] == [.newest(200)])
    }
}
