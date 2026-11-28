import Foundation
import GRDB
import MailCore
import Testing

@testable import MailStore

/// A mailbox read a window at a time: its newest threads, whether it goes on below them, and the pinned and woken
/// threads below them that the list leads with.
struct ThreadWindowTests {
    private let database: MailDatabase
    private let home = AccountID(rawValue: "home")
    private let work = AccountID(rawValue: "work")
    private let away = AccountID(rawValue: "away")

    /// Five Inbox threads in each account, `<account>0` the newest, and one archived.
    init() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "ThreadWindowTests-\(UUID().uuidString)")
            .appending(path: "mail.sqlite")
        database = try MailDatabase(url: url)
        for account in [home, work, away] {
            try database.save(
                Account(id: account, email: "\(account.rawValue)@example.com", color: .teal, service: .gmail))
        }
        try database.upsert(
            [home, work, away].flatMap { account in (0..<5).map { thread("\(account.rawValue)\($0)", in: account) } }
                + [thread("archived", in: home, labels: [])])
        try database.apply(.accounts([home, work]))
    }

    private func thread(
        _ id: String, in account: AccountID, labels: Set<String> = [SystemLabel.inbox], snippet: String = ""
    ) -> ThreadSummary {
        // The digit orders each account's threads; the accounts interleave, home before work at each.
        let index = Double(id.last?.wholeNumberValue ?? 9)
        let offset: Double = account == home ? 0 : account == work ? 1 : 2
        return ThreadSummary(
            id: ThreadSummary.ID(accountID: account, threadID: id), subject: id, snippet: snippet,
            sender: Contact(name: nil, address: "x@example.com"),
            date: Date(timeIntervalSince1970: 1_800_000_000 - index * 600 - offset * 60),
            isUnread: true, messageCount: 1, labelIDs: labels)
    }

    private func first(_ stream: AsyncThrowingStream<ThreadListing, any Error>) async throws -> ThreadListing {
        var iterator = stream.makeAsyncIterator()
        return try #require(try await iterator.next(isolation: #isolation))
    }

    private func ids(_ threads: [ThreadSummary]) -> [String] { threads.map(\.id.threadID) }

    @Test func aWindowListsTheNewestAndSaysTheMailboxGoesOn() async throws {
        let listing = try await first(database.threads(in: .inbox, window: .newest(3)))
        #expect(ids(listing.threads) == ["home0", "work0", "home1"])
        #expect(listing.reach == .more)
        #expect(listing.held.isEmpty)
    }

    @Test(arguments: [ThreadWindow.newest(10), .newest(11), .whole])
    func aWindowAsLongAsTheMailboxReachesItsEnd(_ window: ThreadWindow) async throws {
        let listing = try await first(database.threads(in: .inbox, window: window))
        #expect(listing.threads.count == 10, "the Focus leaves out the third account")
        #expect(listing.reach == .whole)
    }

    @Test func pinnedAndWokenThreadsBelowTheWindowAreHeld() async throws {
        try database.setPins([
            ThreadSummary.ID(accountID: home, threadID: "home4"): true,
            // In the window already, and out of the Inbox.
            ThreadSummary.ID(accountID: home, threadID: "home0"): true,
            ThreadSummary.ID(accountID: home, threadID: "archived"): true,
            // Hidden by the Focus.
            ThreadSummary.ID(accountID: away, threadID: "away4"): true,
        ])
        try database.setSnoozes([
            ThreadSummary.ID(accountID: work, threadID: "work3"): .woke(at: .now),
            ThreadSummary.ID(accountID: work, threadID: "work4"): .asleep(until: .distantFuture, keeper: .thisDevice),
        ])
        let listing = try await first(database.threads(in: .inbox, window: .newest(3)))
        #expect(ids(listing.threads) == ["home0", "work0", "home1"])
        #expect(ids(listing.held) == ["work3", "home4"], "newest first, as the mailbox orders them")
    }

    @Test func aWholeListHoldsNothingApart() async throws {
        try database.setPins([ThreadSummary.ID(accountID: home, threadID: "home4"): true])
        let listing = try await first(database.threads(in: .inbox, window: .whole))
        #expect(listing.held.isEmpty)
        #expect(listing.threads.count == 10)
    }

    @Test func oneAccountsMailboxIsWindowedOnItsOwnThreads() async throws {
        let listing = try await first(
            database.threads(in: Mailbox(labelID: SystemLabel.inbox, accountID: work), window: .newest(2)))
        #expect(ids(listing.threads) == ["work0", "work1"])
        #expect(listing.reach == .more)
    }

    @Test func anAccountOutsideTheFocusIsListedInItsOwnMailbox() async throws {
        let listing = try await first(
            database.threads(in: Mailbox(labelID: SystemLabel.inbox, accountID: away), window: .newest(5)))
        #expect(listing.threads.count == 5)
        #expect(listing.reach == .whole)
    }

    @Test func aCategoryIsWindowedOnItsOwnThreads() async throws {
        try database.upsert([
            thread("home1", in: home, labels: [SystemLabel.inbox, InboxCategory.social.labelID]),
            thread("work2", in: work, labels: [SystemLabel.inbox, InboxCategory.social.labelID]),
            thread("home3", in: home, labels: [SystemLabel.inbox, InboxCategory.social.labelID]),
        ])
        try database.setPins([ThreadSummary.ID(accountID: home, threadID: "home3"): true])
        let social = try await first(database.threads(in: .inbox, category: .social, window: .newest(1)))
        #expect(ids(social.threads) == ["home1"])
        #expect(ids(social.held) == ["home3"])
        #expect(social.reach == .more)
        let primary = try await first(database.threads(in: .inbox, category: .primary, window: .newest(3)))
        #expect(ids(primary.threads) == ["home0", "work0", "work1"])
        #expect(primary.held.isEmpty, "a pin of another category isn't held")
    }

    @Test func aWriteBelowTheWindowChangesNothingItLists() async throws {
        var listings = database.threads(in: .inbox, window: .newest(2)).makeAsyncIterator()
        _ = try await listings.next(isolation: #isolation)
        try database.upsert([thread("home3", in: home, snippet: "edited below")])
        try database.upsert([thread("home0", in: home, snippet: "edited above")])
        let next = try #require(try await listings.next(isolation: #isolation))
        #expect(next.threads.first?.snippet == "edited above", "the write below the window emitted nothing")
    }

    @Test func pinningAThreadBelowTheWindowHoldsIt() async throws {
        var listings = database.threads(in: .inbox, window: .newest(2)).makeAsyncIterator()
        #expect(try await listings.next(isolation: #isolation)?.held.isEmpty == true)
        try database.setPins([ThreadSummary.ID(accountID: home, threadID: "home2"): true])
        #expect(try await listings.next(isolation: #isolation)?.held.map(\.id.threadID) == ["home2"])
    }
}

/// The held threads are found from the pins and snoozes, on the 50,000-thread `Corpus`.
struct HeldThreadsPlanTests {
    @Test(arguments: MailboxQueryPlanTests.Shape.all)
    func heldThreadsAreLookedUpByKeyRatherThanByWalkingTheMailbox(_ shape: MailboxQueryPlanTests.Shape) throws {
        let database = try Corpus.shared.get()
        let held = MailDatabase.held(in: shape.query)
        let plan = try database.read { db in
            try Row.fetchAll(db, sql: "EXPLAIN QUERY PLAN " + held.sortedListing, arguments: held.arguments)
                .map { $0["detail"] as String }
        }
        #expect(!plan.contains { $0.hasPrefix("SCAN thread") || $0.hasPrefix("SCAN threadLabel") }, "\(plan)")
        #expect(plan.contains { $0.hasPrefix("SEARCH thread USING INDEX sqlite_autoindex_thread_1") }, "\(plan)")
    }
}
