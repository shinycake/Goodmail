import Foundation
import MailCore
import Testing

@testable import MailStore

/// A Focus filter narrows the views that blend every account to the accounts it names.
struct FocusStoreTests {
    private let database: MailDatabase
    private let work = Account(id: AccountID(rawValue: "work"), email: "me@work.example", color: .blue, service: .gmail)
    private let home = Account(
        id: AccountID(rawValue: "home"), email: "me@home.example", color: .teal, service: .icloud)
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "FocusStoreTests-\(UUID().uuidString)")
            .appending(path: "mail.sqlite")
        database = try MailDatabase(url: url)
        try database.save(work)
        try database.save(home)
        try database.upsert([thread("w", in: work), thread("h", in: home)])
    }

    private func thread(_ id: String, in account: Account) -> ThreadSummary {
        ThreadSummary(
            id: ThreadSummary.ID(accountID: account.id, threadID: id), subject: "Subject \(id)", snippet: "",
            sender: Contact(name: nil, address: "\(id)@example.com"), date: now, isUnread: true, messageCount: 1,
            labelIDs: [SystemLabel.inbox])
    }

    private func blendedInbox() throws -> [String] {
        try database.threads(in: .inbox, limit: 10).map(\.id.threadID).sorted()
    }

    @Test func everyAccountShowsUntilAFocusNamesSome() throws {
        #expect(try database.focusFilter() == .everyAccount)
        #expect(try blendedInbox() == ["h", "w"])
    }

    @Test func aFocusNarrowsTheBlendedViewsButNotAnAccountsOwn() throws {
        try database.apply(.accounts([work.id]))
        #expect(try database.focusFilter() == .accounts([work.id]))
        #expect(try blendedInbox() == ["w"])
        #expect(try database.threads(in: .allMail, limit: 10).map(\.id.threadID) == ["w"])
        let homeInbox = Mailbox(labelID: SystemLabel.inbox, accountID: home.id)
        #expect(try database.threads(in: homeInbox, limit: 10).map(\.id.threadID) == ["h"])
    }

    @Test func endingTheFocusShowsEveryAccountAgain() throws {
        try database.apply(.accounts([work.id]))
        try database.apply(.everyAccount)
        #expect(try database.focusFilter() == .everyAccount)
        #expect(try blendedInbox() == ["h", "w"])
    }

    @Test func blendedUnreadCountsAndTheBadgeLeaveOutTheOtherAccounts() async throws {
        try database.apply(.accounts([work.id]))
        var directories = database.mailboxDirectory().makeAsyncIterator()
        let directory = try #require(try await directories.next())
        #expect(directory.unreadCounts[.inbox] == 1)
        #expect(directory.unreadCounts[Mailbox(labelID: SystemLabel.inbox, accountID: home.id)] == 1)
        #expect(try database.badgeCount() == 1)
    }

    @Test func anAccountOutsideTheFocusDoesntAlertAndDoesntCatchUpAfter() throws {
        try database.apply(.accounts([work.id]))
        let arrived = thread("new", in: home)
        #expect(try database.claimAlerts(among: [arrived], in: home, now: now).isEmpty)
        try database.apply(.everyAccount)
        #expect(try database.claimAlerts(among: [arrived], in: home, now: now).isEmpty)
    }
}
