import Foundation
import GmailProvider
import MailCore
import MailStore
import MailWrist
import Synchronization
import Testing

@testable import MailWristHost

/// The watch changes the mail of the accounts it reads itself, each change once, and says when a reply didn't go.
@Suite(.timeLimit(.minutes(1)))
struct WristOwnCommandTests {
    typealias Handback = WristOwnHost.Handback

    private let database: MailDatabase
    private let provider = SyncingProvider()
    private let gmail = WristAccount(
        id: AccountID(rawValue: "g"), address: "me@gmail.com", color: .teal, unread: 0, service: .gmail)
    private let host: WristOwnHost
    private let givenBack = GivenBack()
    private let shared = MemoryKeychain()
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    init() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "WristOwnCommandTests-\(UUID().uuidString)")
        database = try MailDatabase(url: folder.appending(path: "mail.sqlite"))
        try shared.set(Data("token".utf8), for: OAuthClient.gmail.refreshTokenKey(gmail.id))
        host = await WristOwnHost(
            database: database, signIns: WristSignIns(device: MemoryKeychain(), shared: shared),
            provider: { [provider] _ in provider }, uploads: folder.appending(path: "Uploads"), now: { Self.now },
            independence: .on, handBack: givenBack.receiver)
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

    /// A host on the same database, as after the app was quit and launched again with the switch `independence`,
    /// before it follows any account.
    private func relaunched(givingBackTo givenBack: GivenBack, independence: WristIndependence = .on) async
        -> WristOwnHost
    {
        await WristOwnHost(
            database: database, signIns: WristSignIns(device: MemoryKeychain(), shared: shared),
            provider: { [provider] _ in provider },
            uploads: FileManager.default.temporaryDirectory.appending(path: "Uploads-\(UUID().uuidString)"),
            now: { Self.now }, independence: independence, handBack: givenBack.receiver)
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

    /// A change queued offline before the owner turned "Mail Without iPhone" off goes to the iPhone instead, and
    /// never from the watch later: the next time the switch is on, the watch starts its copy afresh.
    @Test func aChangeQueuedBeforeTheSwitchWentOffGoesToTheIPhone() async throws {
        provider.failActions(with: URLError(.notConnectedToInternet))
        let archive = command(.archive)
        try await host.execute(archive)

        try await host.follow([gmail], independence: .off)

        #expect(await givenBack.next() == .run(archive))
        provider.failActions(with: nil)
        try await host.follow([gmail], independence: .on)
        try await host.sync()
        #expect(provider.performed.isEmpty)
        #expect(try database.pendingIntents(for: gmail.id).isEmpty)
        #expect(try database.watchChanges().isEmpty)
    }

    /// A change that went before the switch went off isn't given back.
    @Test func aChangeThatWentStaysTheWatchs() async throws {
        try await host.execute(command(.archive))
        #expect(provider.performed == [.archive])
        let read = command(.markRead(true))
        provider.failActions(with: URLError(.notConnectedToInternet))
        try await host.execute(read)

        try await host.follow([gmail], independence: .off)

        #expect(await givenBack.next() == .run(read), "only the one still queued")
    }

    /// At launch, before the watch has followed the iPhone's accounts, a change from an alert waits in the queue; the
    /// switch going off then hands it to the iPhone too.
    @Test func aChangeMadeAtLaunchGoesToTheIPhoneWhenTheSwitchGoesOff() async throws {
        let launched = GivenBack()
        let host = await relaunched(givingBackTo: launched)
        let archive = command(.archive)
        try await host.execute(archive)
        #expect(provider.performed.isEmpty, "no account is served yet")

        try await host.follow([gmail], independence: .off)

        #expect(await launched.next() == .run(archive))
    }

    /// The app quit after a change was queued offline, and the switch went off before the next launch followed it:
    /// the change still goes to the iPhone, from what the database kept.
    @Test func aChangeQueuedBeforeARelaunchGoesToTheIPhone() async throws {
        provider.failActions(with: URLError(.notConnectedToInternet))
        let archive = command(.archive)
        try await host.execute(archive)
        let launched = GivenBack()
        let relaunched = await relaunched(givingBackTo: launched)

        try await relaunched.follow([gmail], independence: .off)

        #expect(await launched.next() == .run(archive))
        try await relaunched.follow([gmail], independence: .on)
        _ = try await relaunched.sources()
        #expect(try database.pendingIntents(for: gmail.id).isEmpty)
        #expect(try database.watchChanges().isEmpty)
    }

    /// What couldn't be kept on the way to the iPhone stays with the watch, and goes the next time; the copy is
    /// forgotten as it is handed over, so none of it can go from the watch meanwhile.
    @Test func aHandBackTurnedDownIsGivenBackNextTime() async throws {
        provider.failActions(with: URLError(.notConnectedToInternet))
        let archive = command(.archive)
        try await host.execute(archive)
        givenBack.refuse(true)
        try await host.follow([gmail], independence: .off)
        try await host.follow([gmail], independence: .on)
        _ = try await host.sources()
        #expect(givenBack.offers == 2, "at the switch going off, and again before serving")
        #expect(try database.pendingIntents(for: gmail.id).isEmpty)
        #expect(try database.watchHandbacks().count == 1)

        givenBack.refuse(false)
        provider.failActions(with: nil)
        try await host.sync()

        #expect(await givenBack.next() == .run(archive))
        #expect(provider.performed.isEmpty)
        #expect(try database.watchHandbacks().isEmpty)
    }

    /// The app was quit after handing a change over and before the iPhone's side kept it: the next launch delivers
    /// it before serving, and the watch never makes it itself.
    @Test func aHandOverCutShortByAQuitIsDeliveredAtTheNextLaunch() async throws {
        provider.failActions(with: URLError(.notConnectedToInternet))
        let archive = command(.archive)
        try await host.execute(archive)
        givenBack.refuse(true)
        try await host.follow([gmail], independence: .off)
        try await host.follow([gmail], independence: .on)
        _ = try await host.sources()
        provider.failActions(with: nil)
        let launched = GivenBack()
        let relaunched = await relaunched(givingBackTo: launched)

        try await relaunched.follow([gmail], independence: .on)
        try await relaunched.sync()

        #expect(await launched.next() == .run(archive))
        #expect(provider.performed.isEmpty)
    }

    /// Launched with the switch stored off, the watch gives back what the last launch left at once, before it
    /// hears from the iPhone, and serves nothing.
    @Test func aLaunchWithTheSwitchOffGivesBackWhatTheLastLaunchLeft() async throws {
        provider.failActions(with: URLError(.notConnectedToInternet))
        let archive = command(.archive)
        try await host.execute(archive)
        provider.failActions(with: nil)
        let launched = GivenBack()

        let relaunched = await relaunched(givingBackTo: launched, independence: .off)

        #expect(await launched.next() == .run(archive))
        try await relaunched.sync()
        #expect(provider.performed.isEmpty)
        await #expect(throws: WristOwnHost.Refusal.switchedOff) { try await relaunched.execute(command(.archive)) }
    }

    /// Once its intents are sent, a change has nothing left to give back, and the watch lets go of it.
    @Test func aChangeThatWentLaterIsLetGo() async throws {
        provider.failActions(with: URLError(.notConnectedToInternet))
        try await host.execute(command(.archive))
        #expect(try database.watchChanges().count == 1)

        provider.failActions(with: nil)
        try await host.sync()

        #expect(provider.performed == [.archive])
        #expect(try database.watchChanges().isEmpty)
    }

    /// A reply the app left on its way when it quit is given back by how far it got: still queued, the iPhone sends
    /// it; turned down, or never answered, it is taken back for the reader.
    @Test(arguments: [
        (OutgoingMessage.Delivery.queued, Handback.run), (.failed(.rejected), Handback.undelivered),
        (.uploading(UploadID()), Handback.unconfirmed),
    ])
    func aReplyLeftOnItsWayIsGivenBackByHowFarItGot(
        _ delivery: OutgoingMessage.Delivery, _ handback: @Sendable (WristCommand) -> Handback
    ) async throws {
        let reply = command(.reply("On my way"))
        let draft = Draft(accountID: gmail.id, subject: "Re: Lunch?", threadID: "t1")
        try database.keepWatchChange(reply.id, command: JSONEncoder().encode(reply))
        try database.addDraft(draft.id, toWatchChange: reply.id)
        try database.enqueue(OutgoingMessage(draft: draft, sendAt: Self.now, delivery: delivery))
        let launched = GivenBack()
        let relaunched = await relaunched(givingBackTo: launched)

        try await relaunched.follow([gmail], independence: .off)

        #expect(await launched.next() == handback(reply))
        #expect(provider.sent == 0)
    }

    /// Launched with the switch stored off, the watch asks the service about a reply whose upload never answered
    /// before it gives it back, though it has followed no account yet: it reads them from its database.
    @Test(arguments: [true, false])
    func aLaunchWithTheSwitchOffAsksAboutAnUnheardReply(went: Bool) async throws {
        provider.sendByUpload(sent: went)
        let reply = command(.reply("On my way"))
        let draft = Draft(accountID: gmail.id, subject: "Re: Lunch?", threadID: "t1")
        try database.keepWatchChange(reply.id, command: JSONEncoder().encode(reply))
        try database.addDraft(draft.id, toWatchChange: reply.id)
        try database.enqueue(OutgoingMessage(draft: draft, sendAt: Self.now, delivery: .uploading(UploadID())))
        // Given back after the reply, so its arrival says the reply's turn is over.
        provider.failActions(with: URLError(.notConnectedToInternet))
        let archive = command(.archive)
        try await host.execute(archive)
        let launched = GivenBack()

        _ = await relaunched(givingBackTo: launched, independence: .off)

        if !went { #expect(await launched.next() == .undelivered(reply), "the service hasn't got it") }
        #expect(await launched.next() == .run(archive), went ? "the reply went: nothing to give back" : "")
        #expect(try database.watchChanges().isEmpty)
    }

    /// The switch going off while a change waits for the service hands the change to the iPhone, when it didn't go.
    @Test func aChangeTheSwitchCutShortGoesToTheIPhone() async throws {
        let (entered, open) = provider.holdActions()
        let archive = command(.archive)
        let archiving = Task { [host] in try await host.execute(archive) }
        var held = entered.makeAsyncIterator()
        await held.next()

        try await host.follow([gmail], independence: .off)
        provider.failActions(with: URLError(.notConnectedToInternet))
        open.finish()

        try await archiving.value
        #expect(await givenBack.next() == .run(archive))
        #expect(provider.performed.isEmpty)
    }

    /// A command made just before the owner turned "Mail Without iPhone" off isn't run behind the switch.
    @Test func aWatchCommandIsRefusedWhileSwitchedOff() async throws {
        try await host.follow([gmail], independence: .off)

        await #expect(throws: WristOwnHost.Refusal.switchedOff) { try await host.execute(command(.archive)) }

        #expect(provider.performed.isEmpty)
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
