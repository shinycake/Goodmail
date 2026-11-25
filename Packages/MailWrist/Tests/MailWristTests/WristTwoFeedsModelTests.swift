import Foundation
import MailCore
import Observation
import Synchronization
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

    /// The watch turned an archive down because the switch went off: the iPhone gets it, and only its feed settles it.
    @Test func anArchiveTheWatchHandsBackGoesToTheIPhone() async throws {
        let model = model()
        model.perform(.archive, on: [row(gmail, "g1")])
        let archive = try #require(model.mailbox.pending.last)

        model.handToPhone(archive)

        var sent: WristCommand?
        for await update in model.updates where update.command?.executor == .phone {
            sent = update.command
            break
        }
        let handed = try #require(sent, "sent on, for the link to give the iPhone")
        #expect(handed.id == archive.id && handed.executor == .phone)
        #expect(model.mailbox.pending == [handed])
        #expect(model.undoable == handed)
        model.receiveOwn(snapshot([], applied: [archive.id]), sources: sources)
        #expect(pending(model) == [archive.id], "the watch's feed no longer settles it")
        model.receive(.snapshot(snapshot([row(icloud, "i1")], applied: [archive.id])))
        #expect(pending(model).isEmpty)
    }

    /// An archive the watch gives back late, after the reader undid it and the undo went to the iPhone, isn't sent:
    /// the iPhone would run it after the undo.
    @Test func aHandBackAfterALaterUndoIsDropped() throws {
        let model = model()
        model.perform(.archive, on: [row(gmail, "g1")])
        let archive = try #require(model.mailbox.pending.last)
        model.receiveOwn(snapshot([], applied: [archive.id]), sources: sources)
        model.undo()
        let undo = try #require(model.mailbox.pending.last)
        model.handToPhone(undo)

        model.handToPhone(archive)

        #expect(model.mailbox.pending.map(\.id) == [undo.id])
    }

    /// The same, once the iPhone has run the undo and its feed settled it.
    @Test func aHandBackAfterAnUndoTheIPhoneRanIsDropped() throws {
        let model = model()
        model.perform(.archive, on: [row(gmail, "g1")])
        let archive = try #require(model.mailbox.pending.last)
        model.receiveOwn(snapshot([], applied: [archive.id]), sources: sources)
        model.undo()
        let undo = try #require(model.mailbox.pending.last)
        model.handToPhone(undo)
        model.receive(.snapshot(snapshot([row(icloud, "i1")], applied: [undo.id])))
        #expect(model.mailbox.pending.isEmpty)

        model.handToPhone(archive)

        #expect(model.mailbox.pending.isEmpty)
    }

    /// The watch gives the same back again after it was quit before letting go: the iPhone still gets each change once.
    @Test func theSameHandBacksTwiceAreOneChange() throws {
        let model = model()
        model.perform(.archive, on: [row(gmail, "g1")])
        model.reply("On my way", in: row(gmail, "g1").id)
        let (archive, reply) = (model.mailbox.pending[0], model.mailbox.pending[1])

        for _ in 0..<2 {
            model.handToPhone(archive)
            model.handToPhone(reply)
        }

        #expect(pending(model) == [archive.id, reply.id])
        #expect(model.mailbox.pending.allSatisfy { $0.executor == .phone })
    }

    /// A change handed to the iPhone long after the reader made it waits as long as one made then.
    @Test func aChangeHandedOverLateWaitsFromTheHandOver() throws {
        let clock = Mutex(now)
        let model = WristInboxModel(now: { clock.withLock { $0 } })
        model.receiveOwn(snapshot([row(gmail, "g1")]), sources: sources)
        model.perform(.archive, on: [row(gmail, "g1")])
        let archive = try #require(model.mailbox.pending.last)
        clock.withLock { $0 = now.addingTimeInterval(25 * 60 * 60) }

        model.handToPhone(archive)
        model.receive(.snapshot(snapshot([row(icloud, "i1")])))

        #expect(pending(model) == [archive.id], "still waiting for the iPhone")
        let stored = try JSONDecoder().decode(WristMailbox.self, from: JSONEncoder().encode(model.mailbox))
        #expect(stored == model.mailbox)
        clock.withLock { $0 = now.addingTimeInterval(50 * 60 * 60) }
        model.receive(.snapshot(snapshot([row(icloud, "i1")])))
        #expect(pending(model).isEmpty, "a day after the hand-over, it was lost")
    }

    /// A later change through the iPhone that sets something else on the conversation doesn't hold a hand-back up.
    @Test func aHandBackAfterAnotherKindOfChangeGoes() throws {
        let model = model()
        model.perform(.markRead(true), on: [row(gmail, "g1")])
        let read = try #require(model.mailbox.pending.last)
        model.receiveOwn(snapshot([row(gmail, "g1")], applied: [read.id]), sources: sources)
        model.perform(.pin(true), on: [row(gmail, "g1")])

        model.handToPhone(read)

        #expect(model.mailbox.pending.last?.id == read.id)
        #expect(model.mailbox.pending.last?.executor == .phone)
    }

    /// A reply the watch couldn't tell went shows among the replies that didn't go, as one that may have.
    @Test func aReplyThatMayHaveGoneSaysSo() throws {
        let model = model()
        model.reply("On my way", in: row(gmail, "g1").id)
        let reply = try #require(model.mailbox.pending.last)

        model.couldntConfirm(reply)

        #expect(model.undelivered == [reply])
        #expect(model.mayHaveGone(reply))
        let stored = try JSONDecoder().decode(WristMailbox.self, from: JSONEncoder().encode(model.mailbox))
        #expect(stored == model.mailbox)
        model.forget(reply)
        #expect(!model.mayHaveGone(reply))
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
        let threads = WristThreads(
            patience: { throw CancellationError() },
            fetching: .own(fetch: { _ in throw URLError(.timedOut) }, direct: [gmail]))
        let id = row(gmail, "g1").id

        await threads.load(id)

        #expect(threads.state(of: id) == .failed(FailureReason(URLError(.timedOut))))
    }

    @Test func aDirectConversationComesFromTheWatch() async {
        let id = row(gmail, "g1").id
        let thread = WristThread(id: id, subject: "Lunch", bubbles: [], earlier: 0, isGroup: false, code: nil)
        let threads = WristThreads(patience: {}, fetching: .own(fetch: { _ in .thread(thread) }, direct: [gmail]))

        await threads.load(id)

        #expect(threads.state(of: id) == .loaded(thread))
    }

    /// The watch's own host can say which accounts it reads after a conversation opened, as when an alert or a
    /// background refresh launched the app: from then on, the conversation comes from the watch.
    @Test func aConversationTurnsTheWatchsOnceItsHostReadsTheAccount() async {
        let id = row(gmail, "g1").id
        let thread = WristThread(id: id, subject: "Lunch", bubbles: [], earlier: 0, isGroup: false, code: nil)
        let threads = WristThreads(patience: { throw CancellationError() })
        #expect(!threads.readsItself(gmail))

        threads.readDirectly([gmail]) { _ in .thread(thread) }

        #expect(threads.readsItself(gmail))
        #expect(!threads.readsItself(icloud))
        await threads.load(id)
        #expect(threads.state(of: id) == .loaded(thread))
    }

    /// Each own snapshot names the accounts again; the same accounts don't redraw the conversation screens.
    @Test func theSameDirectAccountsAgainChangeNothing() {
        let threads = WristThreads(patience: {})
        threads.readDirectly([gmail]) { id in .gone(id) }
        let changed = Changed()
        withObservationTracking {
            _ = threads.readsItself(gmail)
        } onChange: {
            changed.mark()
        }

        threads.readDirectly([gmail]) { id in .gone(id) }
        #expect(!changed.value)
        threads.readDirectly([gmail, icloud]) { id in .gone(id) }
        #expect(changed.value)
    }

    @Test func aRelayedConversationWithTheIPhoneAwaySaysSo() async {
        let threads = WristThreads(
            patience: {}, fetching: .own(fetch: { _ in throw URLError(.timedOut) }, direct: [gmail]))
        let id = row(icloud, "i1").id

        await threads.load(id)

        #expect(threads.state(of: id) == .phoneAway)
    }
}

/// Whether an observed value changed.
private final class Changed: Sendable {
    private let changed = Mutex(false)

    var value: Bool { changed.withLock { $0 } }

    func mark() { changed.withLock { $0 = true } }
}
