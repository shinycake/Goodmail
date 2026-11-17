import Foundation
import MailCore
import Testing

@testable import MailWrist

/// The reader's changes show at once and stay shown until the iPhone's snapshot confirms them.
struct WristMailboxTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let work = AccountID(rawValue: "work")

    private func row(_ id: String, minutesAgo: Double, unread: Bool = true, pinned: Bool = false) -> WristRow {
        WristRow(
            id: ThreadSummary.ID(accountID: work, threadID: id), sender: Contact(name: nil, address: "a@example.com"),
            subject: id, snippet: "", date: now.addingTimeInterval(-minutesAgo * 60), isUnread: unread,
            messageCount: 1, isPinned: pinned, code: nil)
    }

    private func snapshot(_ rows: [WristRow], applied: [UUID] = []) -> WristSnapshot {
        WristSnapshot(
            madeAt: now,
            accounts: [
                WristAccount(
                    id: work, address: "me@work.example", color: .orange, unread: rows.filter(\.isUnread).count)
            ],
            rows: rows, applied: applied)
    }

    private func command(_ kind: WristCommand.Kind, _ ids: String..., minutesAgo: Double = 0) -> WristCommand {
        WristCommand(
            threads: ids.map { ThreadSummary.ID(accountID: work, threadID: $0) }, kind: kind,
            madeAt: now.addingTimeInterval(-minutesAgo * 60))
    }

    private var three: [WristRow] { [row("a", minutesAgo: 1), row("b", minutesAgo: 2), row("c", minutesAgo: 3)] }

    @Test(arguments: [WristCommand.Kind.archive, .trash])
    func removingTakesTheRowAndItsUnreadCount(kind: WristCommand.Kind) throws {
        var mailbox = WristMailbox(snapshot: snapshot(three))
        mailbox.perform(command(kind, "b"))
        let shown = try #require(mailbox.shown)
        #expect(shown.rows.map(\.id.threadID) == ["a", "c"])
        #expect(shown.unread == 2)
    }

    @Test func snoozingTakesTheRowOutAndUndoBringsItBack() throws {
        var mailbox = WristMailbox(snapshot: snapshot(three))
        let snooze = command(.snooze(until: now.addingTimeInterval(3600)), "b")
        mailbox.perform(snooze)
        #expect(try #require(mailbox.shown).rows.map(\.id.threadID) == ["a", "c"])

        let undone = mailbox.undo(snooze, now: now)
        #expect(undone?.kind == .unsnooze)
        #expect(try #require(mailbox.shown).rows.map(\.id.threadID) == ["a", "b", "c"])
    }

    @Test func markingReadKeepsTheRowAndLowersTheCount() throws {
        var mailbox = WristMailbox(snapshot: snapshot(three))
        mailbox.perform(command(.markRead(true), "a", "c"))
        let shown = try #require(mailbox.shown)
        #expect(shown.rows.map(\.isUnread) == [false, true, false])
        #expect(shown.unread == 1)
    }

    @Test func pinningMovesTheRowToTheTop() throws {
        var mailbox = WristMailbox(snapshot: snapshot(three))
        mailbox.perform(command(.pin(true), "c"))
        #expect(try #require(mailbox.shown).rows.map(\.id.threadID) == ["c", "a", "b"])
        mailbox.perform(command(.pin(false), "c"))
        #expect(try #require(mailbox.shown).rows.map(\.id.threadID) == ["a", "b", "c"])
    }

    @Test(arguments: [WristCommand.Kind.moveToInbox, .untrash])
    func movingBackWaitsForTheIPhonesRow(kind: WristCommand.Kind) {
        var mailbox = WristMailbox(snapshot: snapshot(three))
        mailbox.perform(command(kind, "z"))
        #expect(mailbox.shown == snapshot(three))
    }

    @Test func aChangeStaysOverAnOlderSnapshotUntilOneConfirmsIt() throws {
        var mailbox = WristMailbox(snapshot: snapshot(three))
        let archive = command(.archive, "a")
        mailbox.perform(archive)

        mailbox.receive(snapshot(three), now: now)
        #expect(try #require(mailbox.shown).rows.map(\.id.threadID) == ["b", "c"], "The iPhone hasn't run it yet")

        mailbox.receive(snapshot(Array(three.dropFirst()), applied: [archive.id]), now: now)
        #expect(mailbox.pending.isEmpty)
        #expect(try #require(mailbox.shown).rows.map(\.id.threadID) == ["b", "c"])
    }

    @Test func aChangeTheIPhoneNeverConfirmsIsDroppedAfterADay() {
        var mailbox = WristMailbox(snapshot: snapshot(three))
        mailbox.perform(command(.archive, "a", minutesAgo: 24 * 60 + 1))
        mailbox.perform(command(.archive, "b", minutesAgo: 60))
        mailbox.receive(snapshot(three), now: now)
        #expect(mailbox.pending.map(\.threads.first?.threadID) == ["b"])
    }

    @Test func undoBringsTheRowBackAtOnceAndTellsTheIPhone() throws {
        var mailbox = WristMailbox(snapshot: snapshot(three))
        let archive = command(.archive, "a")
        mailbox.perform(archive)

        let undone = mailbox.undo(archive, now: now)
        let inverse = try #require(undone)
        #expect(inverse.kind == .moveToInbox)
        #expect(inverse.threads == archive.threads)
        #expect(inverse.id != archive.id)
        #expect(mailbox.pending == [inverse])
        #expect(try #require(mailbox.shown).rows.map(\.id.threadID) == ["a", "b", "c"])
    }

    @Test func aReplyTheIPhoneCouldntSendIsKeptToSendAgain() {
        var mailbox = WristMailbox(snapshot: snapshot(three))
        let reply = command(.reply("On my way."), "a")
        let archive = command(.archive, "b")
        mailbox.perform(reply)
        mailbox.perform(archive)

        var failed = snapshot(three, applied: [reply.id, archive.id])
        failed.failed = [reply.id, archive.id]
        mailbox.receive(failed, now: now)
        #expect(mailbox.pending.isEmpty)
        #expect(mailbox.undelivered == [reply], "A failed swipe just shows the mail as it is")

        mailbox.forget(reply)
        #expect(mailbox.undelivered.isEmpty)
    }

    @Test func aMailboxStoredBeforeUndeliveredRepliesDecodes() throws {
        let json = #"{"pending":[]}"#
        let mailbox = try JSONDecoder().decode(WristMailbox.self, from: Data(json.utf8))
        #expect(mailbox == WristMailbox())
    }

    @Test func nothingToShowBeforeTheFirstSnapshot() {
        var mailbox = WristMailbox()
        mailbox.perform(command(.archive, "a"))
        #expect(mailbox.shown == nil)
    }
}
