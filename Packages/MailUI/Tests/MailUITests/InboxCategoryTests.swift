import Foundation
import MailCore
import Testing

@testable import MailUI

@MainActor
struct InboxCategoryTests {
    private let account = Account(id: AccountID(rawValue: "a"), email: "a@example.com", color: .teal)

    private func thread(_ id: String) -> ThreadSummary {
        ThreadSummary(
            id: ThreadSummary.ID(accountID: account.id, threadID: id),
            subject: id, snippet: "", sender: Contact(name: nil, address: "x@example.com"),
            date: Date(timeIntervalSince1970: 1_800_000_000), isUnread: true, messageCount: 1, labelIDs: ["INBOX"])
    }

    /// A store with one thread per category, named after it, and these unread counts.
    private func viewModel(
        unread: [InboxCategory: Int] = [:], selected: InboxCategory = .primary,
        didSelect: @escaping (InboxCategory) -> Void = { _ in },
        loadOlder: @escaping () async throws -> Bool = { false }
    ) -> MailboxViewModel {
        MailboxViewModel(
            accounts: [account],
            source: .categorised(
                InboxCategories(
                    threads: { [thread] category in
                        AsyncThrowingStream { $0.yield(category == .forums ? [] : [thread(category.rawValue)]) }
                    },
                    unreadCounts: { AsyncThrowingStream { $0.yield(unread) } },
                    didSelect: didSelect),
                selected: selected),
            refresh: {},
            loadOlder: loadOlder)
    }

    private func shownThreads(_ viewModel: MailboxViewModel) -> [String] {
        viewModel.sections.flatMap { $0.threads.map(\.id.threadID) }
    }

    /// Lets the observation tasks run until `condition` holds.
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<1_000 where !condition() { await Task.yield() }
        #expect(condition())
    }

    @Test func theInboxOpensOnPrimary() async {
        let viewModel = viewModel(unread: [.primary: 2, .social: 1])
        let observing = Task { await viewModel.observe() }
        defer { observing.cancel() }

        #expect(viewModel.category == .primary)
        await waitUntil { shownThreads(viewModel) == ["primary"] }
        await waitUntil { viewModel.categoryUnreadCounts == [.primary: 2, .social: 1] }
    }

    @Test func selectingACategoryFiltersTheList() async {
        var picked: [InboxCategory] = []
        let viewModel = viewModel(didSelect: { picked.append($0) })
        let observing = Task { await viewModel.observe() }
        defer { observing.cancel() }
        await waitUntil { shownThreads(viewModel) == ["primary"] }

        viewModel.select(.promotions)
        #expect(viewModel.category == .promotions)
        await waitUntil { shownThreads(viewModel) == ["promotions"] }
        viewModel.select(.social)
        await waitUntil { shownThreads(viewModel) == ["social"] }
        #expect(picked == [.promotions, .social])
    }

    @Test func aRebuiltListOpensOnTheCategoryLastShown() async {
        let viewModel = viewModel(selected: .updates)
        let observing = Task { await viewModel.observe() }
        defer { observing.cancel() }
        await waitUntil { shownThreads(viewModel) == ["updates"] }
    }

    @Test func anEmptyCategoryPointsToAnotherWithUnreadMail() async {
        let viewModel = viewModel(unread: [.forums: 0, .social: 3], selected: .forums)
        let observing = Task { await viewModel.observe() }
        defer { observing.cancel() }
        await waitUntil { viewModel.hasLoaded && viewModel.categoryUnreadCounts[.social] == 3 }

        #expect(viewModel.sections.isEmpty)
        #expect(viewModel.categoryWithUnread == .social)
        viewModel.select(.social)
        #expect(viewModel.categoryWithUnread == nil, "nothing unread outside Social")
    }

    @Test func aShortCategoryDoesNotPageTheWholeInbox() async {
        var pages = 0
        let viewModel = viewModel(
            selected: .forums,
            loadOlder: {
                pages += 1
                return true
            })
        let observing = Task { await viewModel.observe() }
        defer { observing.cancel() }
        await waitUntil { viewModel.hasLoaded }
        viewModel.select(.social)
        await waitUntil { shownThreads(viewModel) == ["social"] }
        for _ in 0..<100 { await Task.yield() }

        #expect(pages == 0)
        #expect(!viewModel.isLoadingOlder)
    }

    @Test func aShortUncategorisedListFetchesOlderMail() async {
        var pages = 0
        let viewModel = MailboxViewModel(
            mailbox: .spam, accounts: [account], source: .flat { AsyncThrowingStream { $0.yield([]) } },
            refresh: {},
            loadOlder: {
                pages += 1
                return false
            })
        let observing = Task { await viewModel.observe() }
        defer { observing.cancel() }
        await waitUntil { pages == 1 }
    }

    @Test func otherMailboxesHaveNoCategories() async {
        let viewModel = MailboxViewModel(
            mailbox: .starred, accounts: [account],
            source: .flat { [thread] in
                AsyncThrowingStream {
                    $0.yield([thread("starred")])
                    $0.finish()
                }
            },
            refresh: {})
        await viewModel.observe()
        #expect(viewModel.category == nil)
        viewModel.select(.social)
        #expect(viewModel.category == nil)
        #expect(shownThreads(viewModel) == ["starred"])
    }
}
