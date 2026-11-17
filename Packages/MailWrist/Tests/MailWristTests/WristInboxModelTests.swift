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

    @Test func followsUntilTheReadingsEnd() async {
        let model = WristInboxModel()
        let full = snapshot(accounts: [account], rows: [row])
        let (readings, continuation) = AsyncStream.makeStream(of: WristSnapshot.Reading.self)
        continuation.yield(.newerVersion)
        continuation.yield(.snapshot(full))
        continuation.finish()

        await model.follow(readings)
        #expect(model.state == .list(full))
    }
}
