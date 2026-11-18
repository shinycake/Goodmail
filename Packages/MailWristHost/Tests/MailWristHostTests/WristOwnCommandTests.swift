import Foundation
import GmailProvider
import MailCore
import MailStore
import MailWrist
import Synchronization
import Testing

@testable import MailWristHost

/// The watch changes the mail of the accounts it reads itself, each change once, and says when a reply didn't go.
struct WristOwnCommandTests {
    private let database: MailDatabase
    private let provider = SyncingProvider()
    private let gmail = WristAccount(
        id: AccountID(rawValue: "g"), address: "me@gmail.com", color: .teal, unread: 0, service: .gmail)
    private let host: WristOwnHost
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    init() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "WristOwnCommandTests-\(UUID().uuidString)")
        database = try MailDatabase(url: folder.appending(path: "mail.sqlite"))
        let shared = MemoryKeychain()
        try shared.set(Data("token".utf8), for: OAuthClient.gmail.refreshTokenKey(gmail.id))
        host = WristOwnHost(
            database: database, signIns: WristSignIns(device: MemoryKeychain(), shared: shared),
            provider: { [provider] _ in provider }, uploads: folder.appending(path: "Uploads"), now: { Self.now })
        let thread = ThreadSummary(
            id: id, subject: "Lunch?", snippet: "", sender: Contact(name: "Noa", address: "noa@x.com"),
            date: Self.now - 60, isUnread: true, messageCount: 1, labelIDs: ["INBOX", "UNREAD"])
        try database.save(Account(id: gmail.id, email: gmail.address, color: .teal, service: .gmail))
        try database.upsert([thread])
        provider.setMessages(
            [
                Message(
                    id: Message.ID(accountID: gmail.id, messageID: "m1"), threadID: "t1",
                    from: Contact(name: "Noa", address: "noa@x.com"), to: [Contact(name: nil, address: gmail.address)],
                    subject: "Lunch?", date: Self.now - 60, body: MessageBody(plain: "Lunch?"))
            ], inThread: "t1")
        try await host.follow([gmail], independence: .on)
    }

    private var id: ThreadSummary.ID { ThreadSummary.ID(accountID: gmail.id, threadID: "t1") }

    private func command(_ kind: WristCommand.Kind, executor: WristExecutor = .watch) -> WristCommand {
        WristCommand(threads: [id], kind: kind, madeAt: Self.now, executor: executor)
    }

    private func inbox() async throws -> [String] {
        var snapshots = host.snapshots().makeAsyncIterator()
        return try #require(try await snapshots.next()).rows.map(\.id.threadID)
    }

    private func server(sent: SentSnapshots = SentSnapshots()) -> WristServer {
        WristServer(
            applied: [], execute: { [host] in try await host.execute($0) },
            send: { snapshot in sent.snapshots.withLock { $0.append(snapshot) } }, remember: { _ in })
    }

    @Test func aConversationIsFetchedFromTheAccountsServiceBeforeAnySync() async throws {
        let reply = try await host.conversation(id)

        guard case .thread(let thread) = reply else {
            Issue.record("Expected a conversation, got \(reply)")
            return
        }
        #expect(thread.subject == "Lunch?")
        #expect(thread.bubbles.count == 1)
    }

    @Test func aCommandDeliveredTwiceRunsOnce() async throws {
        let server = server()
        let archive = command(.archive)

        try await server.received(archive)
        try await server.received(archive)

        #expect(provider.performed == [.archive])
        #expect(try await inbox().isEmpty)
    }

    @Test func undoingAnArchiveBringsTheRowBackAndQueuesTheInverse() async throws {
        let archive = command(.archive)
        try await host.execute(archive)

        try await host.execute(try #require(archive.inverse(madeAt: Self.now)))

        #expect(try await inbox() == ["t1"])
        #expect(provider.performed == [.archive, .moveToInbox])
    }

    @Test func aReplyIsSentOnce() async throws {
        let server = server()
        let reply = command(.reply("On my way"))

        try await server.received(reply)
        try await server.received(reply)

        #expect(provider.sent == 1)
    }

    @Test func aReplyThatCantGoIsReportedAndTakenBack() async throws {
        let sent = SentSnapshots()
        let server = server(sent: sent)
        await server.inboxChanged(WristSnapshot(madeAt: Self.now, accounts: [], rows: []))
        provider.failSends(with: URLError(.notConnectedToInternet))
        let reply = command(.reply("On my way"))

        await #expect(throws: WristOwnHost.Refusal.replyNotSent) { try await server.received(reply) }

        #expect(sent.snapshots.withLock { $0.last?.failed } == [reply.id])
        provider.failSends(with: nil)
        await host.catchUp()
        #expect(provider.sent == 0, "the reply was taken back, so it never goes later")
    }

    @Test func offlineAnIntentWaitsForTheNextCatchUp() async throws {
        provider.failActions(with: URLError(.notConnectedToInternet))
        try await host.execute(command(.archive))
        #expect(try database.pendingIntents(for: gmail.id).count == 1)

        provider.failActions(with: nil)
        await host.catchUp()

        #expect(provider.performed == [.archive])
        #expect(try database.pendingIntents(for: gmail.id).isEmpty)
    }

    @Test(arguments: [
        WristCommand.Kind.archive, .pin(true), .snooze(until: Date(timeIntervalSince1970: 1_800_003_600)),
    ])
    func theIPhonesCommandsAreRefused(_ kind: WristCommand.Kind) async throws {
        let executor: WristExecutor = kind == .archive ? .phone : .watch

        await #expect(throws: WristOwnHost.Refusal.iPhoneCommand) {
            try await host.execute(command(kind, executor: executor))
        }

        #expect(provider.performed.isEmpty)
    }
}

/// What a server handed to the watch.
private final class SentSnapshots: Sendable {
    let snapshots = Mutex<[WristSnapshot]>([])
}
