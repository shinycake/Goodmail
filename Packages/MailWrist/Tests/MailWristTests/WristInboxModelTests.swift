import Foundation
import MailCore
import Testing

@testable import MailWrist

/// What the watch's Inbox screen shows for each snapshot the iPhone sends.
@MainActor
struct WristInboxModelTests {
    private let account = WristAccount(
        id: AccountID(rawValue: "a1"), address: "me@work.example", color: .teal, unread: 1)
    private let row = WristRow(
        id: ThreadSummary.ID(accountID: AccountID(rawValue: "a1"), threadID: "t1"),
        sender: Contact(name: "Maya", address: "maya@example.com"), subject: "Lunch", snippet: "", date: .now,
        isUnread: true, messageCount: 1, isPinned: false, code: nil)

    private func snapshot(accounts: [WristAccount], rows: [WristRow]) -> WristSnapshot {
        WristSnapshot(madeAt: .now, accounts: accounts, rows: rows)
    }

    @Test func waitsForTheIPhoneUntilSomethingArrives() {
        #expect(WristInboxModel().state == .waitingForPhone)
    }

    @Test func showsWhatArrived() {
        let model = WristInboxModel()
        let empty = snapshot(accounts: [account], rows: [])
        let full = snapshot(accounts: [account], rows: [row])

        model.receive(.snapshot(snapshot(accounts: [], rows: [])))
        #expect(model.state == .noAccounts)
        model.receive(.snapshot(empty))
        #expect(model.state == .caughtUp(empty))
        model.receive(.snapshot(full))
        #expect(model.state == .list(full))
        model.receive(.newerVersion)
        #expect(model.state == .updateNeeded)
    }

    @Test func anUpdateBringsTheListBackAfterAnUpdateNeeded() {
        let model = WristInboxModel()
        let full = snapshot(accounts: [account], rows: [row])
        model.receive(.newerVersion)
        model.receive(.snapshot(full))
        #expect(model.state == .list(full))
    }

    @Test func aSwipeShowsAtOnceAndGoesToTheIPhone() async throws {
        let model = WristInboxModel()
        model.receive(.snapshot(snapshot(accounts: [account], rows: [row])))
        model.perform(.archive, on: [row])

        guard case .caughtUp = model.state else {
            Issue.record("Expected the archived row gone, got \(model.state)")
            return
        }
        var updates = model.updates.makeAsyncIterator()
        #expect(try #require(await updates.next()).command == nil, "The snapshot is stored")
        let update = try #require(await updates.next())
        #expect(update.command?.kind == .archive)
        #expect(update.command?.threads == [row.id])
        #expect(update.mailbox == model.mailbox)
        #expect(model.undoable == update.command)
    }

    @Test func undoPutsTheRowBackAndSendsTheInverse() async throws {
        let model = WristInboxModel()
        let full = snapshot(accounts: [account], rows: [row])
        model.receive(.snapshot(full))
        model.perform(.archive, on: [row])
        model.undo()

        #expect(model.state == .list(full))
        #expect(model.undoable == nil)
        var updates = model.updates.makeAsyncIterator()
        _ = await updates.next()
        _ = await updates.next()
        #expect(try #require(await updates.next()).command?.kind == .moveToInbox)
    }

    @Test func openingAnUnreadConversationMarksItReadWithNothingToUndo() async throws {
        let model = WristInboxModel()
        model.receive(.snapshot(snapshot(accounts: [account], rows: [row])))
        model.open(row)

        guard case .list(let shown) = model.state else {
            Issue.record("Expected the list, got \(model.state)")
            return
        }
        #expect(shown.rows.map(\.isUnread) == [false])
        #expect(model.undoable == nil)
        var updates = model.updates.makeAsyncIterator()
        _ = await updates.next()
        #expect(try #require(await updates.next()).command?.kind == .markRead(true))
    }

    @Test func openingAReadConversationChangesNothing() {
        let model = WristInboxModel()
        var read = row
        read.isUnread = false
        let full = snapshot(accounts: [account], rows: [read])
        model.receive(.snapshot(full))
        model.open(read)
        #expect(model.state == .list(full))
    }

    @Test func aReplyGoesToTheIPhoneWithNothingToUndo() async throws {
        let model = WristInboxModel()
        let full = snapshot(accounts: [account], rows: [row])
        model.receive(.snapshot(full))
        model.reply("Sounds good.", in: row.id)

        #expect(model.state == .list(full))
        #expect(model.undoable == nil)
        var updates = model.updates.makeAsyncIterator()
        _ = await updates.next()
        let update = try #require(await updates.next())
        #expect(update.command?.kind == .reply("Sounds good."))
        #expect(update.command?.threads == [row.id])
    }

    @Test func undoGoesWhenItsTimeIsOver() throws {
        let model = WristInboxModel()
        model.receive(.snapshot(snapshot(accounts: [account], rows: [row])))
        model.perform(.markRead(true), on: [row])
        let first = model.undoable
        model.perform(.markRead(false), on: [row])

        model.keep(try #require(first))
        #expect(model.undoable?.kind == .markRead(false), "Only the change whose time is over goes")
        model.keep(try #require(model.undoable))
        #expect(model.undoable == nil)
    }

    @Test func aStoredMailboxShowsUntilTheIPhoneSendsOne() {
        let full = snapshot(accounts: [account], rows: [row])
        let stored = WristMailbox(snapshot: full)
        let model = WristInboxModel()
        model.restore(stored)
        #expect(model.state == .list(full))

        let fresh = snapshot(accounts: [account], rows: [])
        let current = WristInboxModel()
        current.receive(.snapshot(fresh))
        current.restore(stored)
        #expect(current.state == .caughtUp(fresh), "What the iPhone sent is newer than the store")
    }
}
