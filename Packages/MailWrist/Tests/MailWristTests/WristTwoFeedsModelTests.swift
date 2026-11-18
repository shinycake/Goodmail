import Foundation
import MailCore
import Testing

@testable import MailWrist

/// The watch's models with two feeds: each change goes to the device that runs it, and only that device's feed
/// settles it.
@MainActor
struct WristTwoFeedsModelTests {
    private let gmail = AccountID(rawValue: "gmail")
    private let icloud = AccountID(rawValue: "icloud")
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func row(_ account: AccountID, _ id: String) -> WristRow {
        WristRow(
            id: ThreadSummary.ID(accountID: account, threadID: id), sender: Contact(name: nil, address: "a@x.com"),
            subject: id, snippet: "", date: now, isUnread: true, messageCount: 1, isPinned: false, code: nil)
    }

    private func snapshot(_ rows: [WristRow], applied: [UUID] = [], failed: [UUID] = []) -> WristSnapshot {
        WristSnapshot(
            madeAt: now,
            accounts: [
                WristAccount(id: gmail, address: "me@gmail.com", color: .teal, unread: 0, service: .gmail),
                WristAccount(id: icloud, address: "me@icloud.com", color: .orange, unread: 0, service: .icloud),
            ],
            rows: rows, applied: applied, failed: failed)
    }

    private var sources: [AccountID: WristAccountSource] { [gmail: .direct, icloud: .relayed(.service)] }

    /// A model showing a Gmail row the watch reads itself and an iCloud row from the iPhone.
    private func model(gmailSource: WristAccountSource = .direct) -> WristInboxModel {
        let model = WristInboxModel(now: { [now] in now })
        model.receive(.snapshot(snapshot([row(icloud, "i1")])))
        model.receiveOwn(snapshot([row(gmail, "g1")]), sources: [gmail: gmailSource, icloud: .relayed(.service)])
        return model
    }

    private func pending(_ model: WristInboxModel) -> [UUID] { model.mailbox.pending.map(\.id) }

    @Test func anArchiveOnADirectAccountIsTheWatchsAndOnlyItsFeedConfirmsIt() throws {
        let model = model()
        model.perform(.archive, on: [row(gmail, "g1")])
        let archive = try #require(model.mailbox.pending.last)
        #expect(archive.executor == .watch)

        model.receive(.snapshot(snapshot([row(icloud, "i1")], applied: [archive.id])))
        #expect(pending(model) == [archive.id], "the iPhone didn't run it")

        model.receiveOwn(snapshot([], applied: [archive.id]), sources: sources)
        #expect(pending(model).isEmpty)
    }

    @Test func aPinOnADirectAccountIsTheIPhonesAndItsFeedConfirmsIt() throws {
        let model = model()
        model.perform(.pin(true), on: [row(gmail, "g1")])
        let pin = try #require(model.mailbox.pending.last)
        #expect(pin.executor == .phone)

        model.receiveOwn(snapshot([row(gmail, "g1")], applied: [pin.id]), sources: sources)
        #expect(pending(model) == [pin.id])

        model.receive(.snapshot(snapshot([row(icloud, "i1")], applied: [pin.id])))
        #expect(pending(model).isEmpty)
    }

    @Test func aRelayedAccountsChangeGoesToTheIPhone() throws {
        let model = model()
        model.perform(.archive, on: [row(icloud, "i1")])
        #expect(try #require(model.mailbox.pending.last).executor == .phone)
    }

    @Test func aChangeAcrossBothKindsOfAccountGoesToTheIPhone() throws {
        let model = model()
        model.perform(.archive, on: [row(gmail, "g1"), row(icloud, "i1")])
        #expect(try #require(model.mailbox.pending.last).executor == .phone)
    }

    @Test func aPendingIPhoneChangeStillSettlesAfterItsAccountTurnsDirect() throws {
        let model = model(gmailSource: .relayed(.filling))
        model.perform(.archive, on: [row(gmail, "g1")])
        let archive = try #require(model.mailbox.pending.last)
        #expect(archive.executor == .phone)

        model.receiveOwn(snapshot([]), sources: sources)
        model.receive(.snapshot(snapshot([row(icloud, "i1")], applied: [archive.id])))

        #expect(pending(model).isEmpty)
    }

    @Test func aReplyTheWatchCouldntSendIsUndelivered() throws {
        let model = model()
        model.reply("On my way", in: row(gmail, "g1").id)
        let reply = try #require(model.mailbox.pending.last)

        model.receiveOwn(snapshot([row(gmail, "g1")], applied: [reply.id], failed: [reply.id]), sources: sources)

        #expect(model.undelivered.map(\.id) == [reply.id])
    }

    @Test func aDirectConversationThatFailsToLoadSaysSo() async {
        let threads = WristThreads(patience: { throw CancellationError() }, own: { _ in throw URLError(.timedOut) })
        threads.direct = [gmail]
        let id = row(gmail, "g1").id

        await threads.load(id)

        #expect(threads.state(of: id) == .failed(FailureReason(URLError(.timedOut))))
    }

    @Test func aDirectConversationComesFromTheWatch() async {
        let id = row(gmail, "g1").id
        let thread = WristThread(id: id, subject: "Lunch", bubbles: [], earlier: 0, isGroup: false, code: nil)
        let threads = WristThreads(patience: {}, own: { _ in .thread(thread) })
        threads.direct = [gmail]

        await threads.load(id)

        #expect(threads.state(of: id) == .loaded(thread))
    }

    @Test func aRelayedConversationWithTheIPhoneAwaySaysSo() async {
        let threads = WristThreads(patience: {}, own: { _ in throw URLError(.timedOut) })
        threads.direct = [gmail]
        let id = row(icloud, "i1").id

        await threads.load(id)

        #expect(threads.state(of: id) == .phoneAway)
    }
}
