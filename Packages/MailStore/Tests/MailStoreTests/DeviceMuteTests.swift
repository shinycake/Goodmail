import Foundation
import MailCore
import Testing

@testable import MailStore

/// Outlook, iCloud and IMAP have no Mute, so the device keeps it: a muted thread leaves the Inbox, and replies that
/// arrive later stay out of it and never alert, until it is unmuted.
struct DeviceMuteTests {
    private let database: MailDatabase
    private let outlook = Account(
        id: AccountID(rawValue: "o1"), email: "me@outlook.com", color: .blue, service: .outlook)
    private let gmail = Account(id: AccountID(rawValue: "g1"), email: "me@gmail.com", color: .teal, service: .gmail)
    private static let start = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "DeviceMuteTests-\(UUID().uuidString)")
            .appending(path: "mail.sqlite")
        database = try MailDatabase(url: url)
        try database.save(outlook)
        try database.save(gmail)
        try database.upsert([thread("t1", in: outlook), thread("t2", in: outlook), thread("t1", in: gmail)])
        // The Inbox was seen as it stands, so only mail that arrives later alerts.
        try database.markSeen(through: Self.start, for: outlook.id, now: Self.start)
    }

    private func thread(
        _ threadID: String, in account: Account, date: Date = start, labels: Set<String> = [SystemLabel.inbox]
    ) -> ThreadSummary {
        ThreadSummary(
            id: ThreadSummary.ID(accountID: account.id, threadID: threadID), subject: "Subject \(threadID)",
            snippet: "", sender: Contact(name: nil, address: "dana@example.com"), date: date, isUnread: true,
            messageCount: 1, labelIDs: labels)
    }

    private var commands: MailCommands {
        MailCommands(store: database, replay: { _ in }, now: { Self.start })
    }

    /// The provider's view of the thread after a fetch: in the Inbox, without `MUTED`, which it doesn't know.
    private func fetch(_ thread: ThreadSummary) throws {
        try database.apply(
            StoreChanges(
                accountID: thread.id.accountID, upserts: [thread], fetchedAt: Self.start.addingTimeInterval(3600)))
    }

    private func inbox(of account: Account) async throws -> [String] {
        var threads = database.threads(in: Mailbox(labelID: SystemLabel.inbox, accountID: account.id))
            .makeAsyncIterator()
        return try await threads.next()?.map(\.id.threadID) ?? []
    }

    private func queuedActions(for account: Account) throws -> [ThreadAction] {
        try database.pendingIntents(for: account.id).map(\.action)
    }

    /// Sends what the account queued, before the next fetch begins, so the fetch shows it done.
    private func replay(_ account: Account) throws {
        for intent in try database.pendingIntents(for: account.id) { try database.markSent(intent.id, at: Self.start) }
    }

    @Test func mutingLeavesTheInboxAndTellsTheProviderOnlyOfTheArchive() async throws {
        let id = thread("t1", in: outlook).id
        try await commands.perform(.mute, on: [id])

        #expect(try await inbox(of: outlook) == ["t2"])
        #expect(try database.thread(id)?.labelIDs == [SystemLabel.muted])
        #expect(try queuedActions(for: outlook) == [.archive])
    }

    @Test func aFetchKeepsTheThreadMuted() async throws {
        let id = thread("t1", in: outlook).id
        try await commands.perform(.mute, on: [id])
        try fetch(thread("t1", in: outlook, labels: []))

        #expect(try database.thread(id)?.labelIDs == [SystemLabel.muted])
    }

    @Test func aReplyStaysOutOfTheInboxAndDoesntAlert() async throws {
        let id = thread("t1", in: outlook).id
        try await commands.perform(.mute, on: [id])
        try replay(outlook)
        let reply = thread("t1", in: outlook, date: Self.start.addingTimeInterval(60))
        try fetch(reply)

        #expect(try await inbox(of: outlook) == ["t2"])
        #expect(try database.thread(id)?.labelIDs == [SystemLabel.muted])
        #expect(try queuedActions(for: outlook) == [.archive], "the reply is archived at the provider too")
        #expect(try database.claimAlerts(among: [reply], in: outlook, now: Self.start).isEmpty)
    }

    @Test func aMutedThreadMovedBackToTheInboxStaysThere() async throws {
        let id = thread("t1", in: outlook).id
        try await commands.perform(.mute, on: [id])
        try await commands.perform(.moveToInbox, on: [id])
        try fetch(thread("t1", in: outlook))

        #expect(Set(try await inbox(of: outlook)) == ["t1", "t2"], "only a newer message is kept out")
        #expect(try database.thread(id)?.labelIDs.contains(SystemLabel.muted) == true)
    }

    @Test func unmutingBringsTheThreadBackAndLetsRepliesIn() async throws {
        let id = thread("t1", in: outlook).id
        try await commands.perform(.mute, on: [id])
        try await commands.perform(.unmute, on: [id])
        #expect(Set(try await inbox(of: outlook)) == ["t1", "t2"])

        let reply = thread("t1", in: outlook, date: Self.start.addingTimeInterval(60))
        try fetch(reply)
        #expect(try database.thread(id)?.labelIDs == [SystemLabel.inbox])
        #expect(try queuedActions(for: outlook) == [.archive, .modifyLabels(add: [SystemLabel.inbox], remove: [])])
        #expect(try database.claimAlerts(among: [reply], in: outlook, now: Self.start).map(\.id) == [id])
    }

    @Test func undoingMuteUnmutes() async throws {
        let id = thread("t1", in: outlook).id
        let commands = commands
        try await commands.undo(try await commands.perform(.mute, on: [id]))

        try fetch(thread("t1", in: outlook, date: Self.start.addingTimeInterval(60)))
        #expect(try database.thread(id)?.labelIDs == [SystemLabel.inbox])
    }

    @Test func gmailKeepsItsOwnMute() async throws {
        let id = thread("t1", in: gmail).id
        try await commands.perform(.mute, on: [id])

        #expect(try queuedActions(for: gmail) == [.mute])
        try replay(gmail)
        try fetch(thread("t1", in: gmail, date: Self.start.addingTimeInterval(60)))
        #expect(try database.thread(id)?.labelIDs == [SystemLabel.inbox], "Gmail's fetch says what is muted")
    }
}
