import Foundation
import MailCore
import Testing

@testable import MailUI

// They follow the store's streams, so one that never finishes fails the test instead of hanging the run.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ListFilterListTests {
    private let account = Account(id: AccountID(rawValue: "a"), email: "a@example.com", color: .teal, service: .gmail)

    private func thread(_ id: String, unread: Bool = false, starred: Bool = false) -> ThreadSummary {
        ThreadSummary(
            id: ThreadSummary.ID(accountID: account.id, threadID: id), subject: id, snippet: "",
            sender: Contact(name: nil, address: "x@example.com"), date: Date(timeIntervalSince1970: 1_800_000_000),
            isUnread: unread, messageCount: 1,
            labelIDs: starred ? [SystemLabel.inbox, SystemLabel.starred] : [SystemLabel.inbox])
    }

    private func viewModel(
        _ threads: [ThreadSummary], filter: ListFilter = .none, withAttachments: Set<ThreadSummary.ID> = [],
        changed: @escaping (ListFilter) -> Void = { _ in }
    ) -> MailboxViewModel {
        MailboxViewModel(
            accounts: [account], source: .flat(.whole { AsyncThrowingStream { $0.yield(threads) } }), filter: filter,
            didChangeFilter: changed, attachmentThreads: { AsyncThrowingStream { $0.yield(withAttachments) } },
            refresh: {})
    }

    private func shown(_ viewModel: MailboxViewModel) -> [String] {
        viewModel.sections.flatMap { $0.threads.map(\.id.threadID) }
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<1_000 where !condition() { await Task.yield() }
        #expect(condition())
    }

    @Test func withoutAFilterEveryThreadShows() async {
        let viewModel = viewModel([thread("a", unread: true), thread("b")])
        let observing = Task { await viewModel.observe() }
        defer { observing.cancel() }
        await waitUntil { shown(viewModel).count == 2 }
        #expect(viewModel.hiddenByFilter == 0)
    }

    @Test func unreadShowsOnlyUnreadThreadsAndCountsTheRest() async {
        let viewModel = viewModel([thread("a", unread: true), thread("b"), thread("c")])
        let observing = Task { await viewModel.observe() }
        defer { observing.cancel() }
        await waitUntil { shown(viewModel).count == 3 }

        viewModel.setFilter(.on([.unread]))
        #expect(shown(viewModel) == ["a"])
        #expect(viewModel.hiddenByFilter == 2)

        viewModel.setFilter(viewModel.filter.toggled())
        #expect(shown(viewModel).count == 3)
        #expect(viewModel.hiddenByFilter == 0)
    }

    @Test func aFilterThatHidesEverythingLeavesAnEmptyListWithTheCountOfWhatItHid() async {
        let viewModel = viewModel([thread("a"), thread("b")], filter: .on([.unread]))
        let observing = Task { await viewModel.observe() }
        defer { observing.cancel() }
        await waitUntil { viewModel.listing.hasAnswered }
        #expect(viewModel.sections.isEmpty)
        #expect(viewModel.hiddenByFilter == 2, "a mailbox that holds mail, not an empty one")
    }

    @Test func severalChoicesAllHaveToHold() async {
        let viewModel = viewModel(
            [thread("a", unread: true, starred: true), thread("b", unread: true), thread("c", starred: true)],
            filter: .on([.unread, .starred]))
        let observing = Task { await viewModel.observe() }
        defer { observing.cancel() }
        await waitUntil { viewModel.listing.hasAnswered }
        #expect(shown(viewModel) == ["a"])
    }

    @Test func withAttachmentsShowsThreadsKnownToHoldFiles() async {
        let withFile = thread("a")
        let viewModel = viewModel(
            [withFile, thread("b")], filter: .on([.withAttachments]), withAttachments: [withFile.id])
        let observing = Task { await viewModel.observe() }
        defer { observing.cancel() }
        await waitUntil { shown(viewModel) == ["a"] }
    }

    @Test func withAttachmentsTurnedOnAgainWaitsForTheStoresNewAnswer() async {
        let withFile = thread("a")
        let threads = [withFile, thread("b")]
        var asked = 0
        let viewModel = MailboxViewModel(
            accounts: [account], source: .flat(.whole { AsyncThrowingStream { $0.yield(threads) } }),
            filter: .on([.withAttachments]), didChangeFilter: { _ in },
            attachmentThreads: {
                asked += 1
                // The first answer comes at once; the second not before the test ends.
                return AsyncThrowingStream { if asked == 1 { $0.yield([withFile.id]) } }
            },
            refresh: {})
        let observing = Task { await viewModel.observe() }
        defer { observing.cancel() }
        await waitUntil { shown(viewModel) == ["a"] }
        viewModel.setFilter(viewModel.filter.toggled())
        await waitUntil { viewModel.attachmentWatch == .off }
        viewModel.setFilter(viewModel.filter.toggled())
        #expect(shown(viewModel).isEmpty, "what was heard before it went off says nothing now")
        await waitUntil { asked == 2 }
        #expect(shown(viewModel).isEmpty)
    }

    @Test func theWindowIsToldOfEachChoiceOnceAndNotOfARepeat() {
        var told: [ListFilter] = []
        let viewModel = viewModel([], changed: { told.append($0) })
        viewModel.setFilter(.on([.starred]))
        viewModel.setFilter(.on([.starred]))
        viewModel.setFilter(viewModel.filter.toggled())
        #expect(told == [.on([.starred]), .off(last: [.starred])])
    }

    @Test func aListWithNoWindowToKeepTheFilterIsNotFiltered() {
        let search = MailboxViewModel(
            accounts: [account], source: .flat(.whole { AsyncThrowingStream { $0.finish() } }), refresh: {})
        #expect(!search.offersFilter)
        search.setFilter(.on([.unread]))
        #expect(search.filter == .none)
    }

    @Test func aNewWindowOpensWithTheFilterOfItsList() {
        let viewModel = viewModel([], filter: .on([.starred]))
        #expect(viewModel.newWindow(for: thread("a").id).filter == .on([.starred]))
    }
}
