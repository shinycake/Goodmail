import Foundation
import MailCore
import MailStore
import MailWrist
import Testing

@testable import MailWristHost

/// The watch sees the Inbox as the iPhone keeps it, and its changes land in the same database.
struct WristMailHostTests {
    private let database: MailDatabase
    private let account = Account(
        id: AccountID(rawValue: "work"), email: "me@work.example", color: .orange, service: .gmail)
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "WristMailHostTests-\(UUID().uuidString)")
            .appending(path: "mail.sqlite")
        database = try MailDatabase(url: url)
        try database.save(account)
    }

    private func id(_ thread: String) -> ThreadSummary.ID {
        ThreadSummary.ID(accountID: account.id, threadID: thread)
    }

    private func thread(_ thread: String, minutesAgo: Double) -> ThreadSummary {
        ThreadSummary(
            id: id(thread), subject: "Subject \(thread)", snippet: "",
            sender: Contact(name: "Noa", address: "noa@x.com"),
            date: now - minutesAgo * 60, isUnread: true, messageCount: 1, labelIDs: ["INBOX", "UNREAD"])
    }

    private func message(_ thread: String, minutesAgo: Double) -> Message {
        Message(
            id: Message.ID(accountID: account.id, messageID: "\(thread)-m"), threadID: thread,
            from: Contact(name: "Noa", address: "noa@x.com"), to: [Contact(name: nil, address: account.email)],
            subject: "Subject \(thread)", date: now - minutesAgo * 60, body: MessageBody(plain: "Lunch?"))
    }

    private func host(_ provider: ScriptedProvider = ScriptedProvider(messages: [:])) -> WristMailHost {
        let commands = MailCommands(store: database, replay: { _ in }, now: { [now] in now })
        return WristMailHost(
            database: database, commands: commands,
            answers: ThreadAnswers(database: database, commands: commands, provider: { _ in provider }))
    }

    private func firstSnapshot(of host: WristMailHost) async throws -> WristSnapshot {
        var snapshots = host.snapshots(now: { [now] in now }).makeAsyncIterator()
        return try #require(try await snapshots.next())
    }

    @Test func aSnapshotListsPinnedThenNewest() async throws {
        try database.upsert([thread("old", minutesAgo: 90), thread("new", minutesAgo: 1)])
        try database.setPins([id("old"): true])
        let snapshot = try await firstSnapshot(of: host())
        #expect(snapshot.rows.map(\.id.threadID) == ["old", "new"])
        #expect(snapshot.accounts.map(\.service) == [.gmail])
        #expect(snapshot.madeAt == now)
    }

    @Test func theIPhonesSnapshotCarriesWhatOnlyItKnows() async throws {
        let outlook = Account(id: AccountID(rawValue: "home"), email: "me@outlook.com", color: .blue, service: .outlook)
        try database.save(outlook)
        try database.upsert([thread("t1", minutesAgo: 1)])
        try database.setPins([id("t1"): true])
        try database.apply(StoreChanges(accountID: account.id, signature: "Kept by Gmail"))
        try database.apply(StoreChanges(accountID: outlook.id, signature: "Only on the iPhone"))
        let commands = MailCommands(store: database, replay: { _ in }, now: { [now] in now })
        let host = WristMailHost(
            database: database, commands: commands,
            answers: ThreadAnswers(
                database: database, commands: commands, provider: { _ in throw ProviderError.notFound }),
            independence: { .on })

        let extras = try #require(try await firstSnapshot(of: host).extras)

        #expect(extras.pinned == [id("t1")])
        #expect(extras.signatures == [outlook.id: "Only on the iPhone"], "Gmail keeps its own")
        #expect(extras.focus == nil)
        #expect(extras.independence == .on)
    }

    @Test func turningTheSwitchOffHandsEveryAccountBackToTheIPhone() async throws {
        try database.upsert([thread("t1", minutesAgo: 1)])
        let commands = MailCommands(store: database, replay: { _ in }, now: { [now] in now })
        let host = WristMailHost(
            database: database, commands: commands,
            answers: ThreadAnswers(
                database: database, commands: commands, provider: { _ in throw ProviderError.notFound }),
            independence: { WristIndependence(mailWithoutIPhone: false) })

        let snapshot = try await firstSnapshot(of: host)
        let independence = try #require(snapshot.extras?.independence)
        let sources = WristAccountSources.resolve(
            accounts: snapshot.accounts, signIns: [account.id], health: [:],
            syncStates: [account.id: .current(cursor: "1")], independence: independence)

        #expect(independence == .off)
        #expect(sources == [account.id: .relayed(.switchedOff)])
    }

    @Test func anArchiveLeavesTheInboxAndIsQueuedForTheService() async throws {
        try database.upsert([thread("t1", minutesAgo: 1)])
        let host = host()
        try await host.execute(WristCommand(threads: [id("t1")], kind: .archive, madeAt: now))
        #expect(try await firstSnapshot(of: host).rows.isEmpty)
        #expect(try database.pendingIntents(for: account.id).count == 1)
    }

    @Test func aConversationComesFromTheStoreWhenItsCurrent() async throws {
        try database.upsert([thread("t1", minutesAgo: 5)])
        try database.save([message("t1", minutesAgo: 5)], inThread: id("t1"))
        let provider = ScriptedProvider(messages: [:])
        let reply = try await host(provider).conversation(id("t1"))
        guard case .thread(let thread) = reply else {
            Issue.record("Expected a conversation, got \(reply)")
            return
        }
        #expect(thread.subject == "Subject t1")
        #expect(provider.fetchCount == 0)
    }

    /// An alert can open a conversation the store hasn't listed yet, as when the watch hasn't synced since it came.
    @Test func aConversationTheStoreDoesntListYetIsFetched() async throws {
        let provider = ScriptedProvider(messages: ["t1": [message("t1", minutesAgo: 1)]])
        let reply = try await host(provider).conversation(id("t1"))
        guard case .thread(let thread) = reply else {
            Issue.record("Expected a conversation, got \(reply)")
            return
        }
        #expect(thread.subject == "Subject t1")
        #expect(provider.fetchCount == 1)
    }

    @Test func aReplyToAConversationTheStoreDoesntListYetIsQueued() async throws {
        let provider = ScriptedProvider(messages: ["t1": [message("t1", minutesAgo: 1)]])
        try await host(provider).execute(WristCommand(threads: [id("t1")], kind: .reply("Yes!"), madeAt: now))
        var outgoing = database.outgoingMessages(inThread: id("t1")).makeAsyncIterator()
        let queued = try #require(try await outgoing.next())
        #expect(queued.count == 1)
    }

    @Test func aConversationOfAnAccountThatsGoneIsGone() async throws {
        let other = ThreadSummary.ID(accountID: AccountID(rawValue: "gone"), threadID: "t1")
        #expect(try await host().conversation(other) == .gone(other))
    }

    @Test func aReplyIsQueuedOnce() async throws {
        try database.upsert([thread("t1", minutesAgo: 5)])
        let provider = ScriptedProvider(messages: ["t1": [message("t1", minutesAgo: 5)]])
        try await host(provider).execute(WristCommand(threads: [id("t1")], kind: .reply("Yes!"), madeAt: now))
        var outgoing = database.outgoingMessages(inThread: id("t1")).makeAsyncIterator()
        let queued = try #require(try await outgoing.next())
        #expect(queued.count == 1)
        #expect(queued.first?.draft.body.plain?.hasPrefix("Yes!") == true)
    }
}
