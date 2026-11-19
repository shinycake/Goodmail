import Foundation
import MailCore
import Testing

@testable import MailWrist

/// The watch takes down an alert the relay sent it once the Inbox it holds says the mail was dealt with.
struct WristHandledAlertsTests {
    private let alertedAt = Date(timeIntervalSince1970: 1_800_000_000)
    private let gmail = AccountID(rawValue: "gmail")
    private let icloud = AccountID(rawValue: "icloud")
    private let sources: [AccountID: WristAccountSource] = [
        AccountID(rawValue: "gmail"): .direct, AccountID(rawValue: "icloud"): .relayed(.service),
    ]

    private func row(_ account: AccountID, _ id: String, minutesAfter: Double = 0, unread: Bool = true) -> WristRow {
        WristRow(
            id: ThreadSummary.ID(accountID: account, threadID: id), sender: Contact(name: nil, address: "a@x.com"),
            subject: id, snippet: "", date: alertedAt.addingTimeInterval(minutesAfter * 60), isUnread: unread,
            messageCount: 1, isPinned: false, code: nil)
    }

    private func snapshot(_ rows: [WristRow], minutesAfter: Double = 1, unread: [AccountID: Int] = [:])
        -> WristSnapshot
    {
        WristSnapshot(
            madeAt: alertedAt.addingTimeInterval(minutesAfter * 60),
            accounts: [
                WristAccount(id: gmail, address: "me@gmail.com", color: .teal, unread: unread[gmail] ?? 1),
                WristAccount(id: icloud, address: "me@icloud.com", color: .orange, unread: unread[icloud] ?? 1),
            ],
            rows: rows)
    }

    private func mailbox(phone: WristSnapshot, own: WristSnapshot? = nil) -> WristMailbox {
        WristMailbox(snapshot: phone, own: own, sources: sources)
    }

    private func alert(_ payload: [String: String]) -> WristDeliveredAlert {
        WristDeliveredAlert(identifier: "a", payload: payload, deliveredAt: alertedAt)
    }

    private let gmailAlert = ["account": "me@gmail.com", "threadID": "t1"]

    @Test func readMailTakesItsAlertDown() {
        let own = snapshot([row(gmail, "t1", unread: false), row(gmail, "t2")])
        #expect(mailbox(phone: snapshot([]), own: own).handledAlerts([alert(gmailAlert)]) == ["a"])
    }

    @Test func unreadMailKeepsItsAlert() {
        let own = snapshot([row(gmail, "t1")])
        #expect(mailbox(phone: snapshot([]), own: own).handledAlerts([alert(gmailAlert)]).isEmpty)
    }

    @Test func aConversationReadBeforeNewerMailInItAlertedKeepsTheAlert() {
        let own = snapshot([row(gmail, "t1", minutesAfter: -60, unread: false)], minutesAfter: -30)
        #expect(mailbox(phone: snapshot([]), own: own).handledAlerts([alert(gmailAlert)]).isEmpty)
    }

    @Test func eachAccountIsJudgedByItsOwnSourcesCopy() {
        // The iPhone's copy still has it unread; the watch reads Gmail itself and has it read.
        let phone = snapshot([row(gmail, "t1"), row(icloud, "i1")])
        let own = snapshot([row(gmail, "t1", unread: false)])
        #expect(mailbox(phone: phone, own: own).handledAlerts([alert(gmailAlert)]) == ["a"])
    }

    @Test func anAccountLeftWithNothingUnreadTakesDownAlertsThatNameNoConversation() {
        let icloudAlert = alert(["accountID": "icloud"])
        let phone = snapshot([row(icloud, "i1")], unread: [icloud: 0])
        #expect(mailbox(phone: phone).handledAlerts([icloudAlert]) == ["a"])
        // A copy that holds nothing as new as the alert can't say, however recently it was sent: the iPhone may not
        // have the mail yet.
        let behind = snapshot([row(icloud, "i1", minutesAfter: -60)], minutesAfter: 5, unread: [icloud: 0])
        #expect(mailbox(phone: behind).handledAlerts([icloudAlert]).isEmpty)
    }

    @Test func mailGoneFromAListThatWouldHoldItTakesItsAlertDown() {
        let own = snapshot([row(gmail, "t2", minutesAfter: 2)])
        #expect(mailbox(phone: snapshot([]), own: own).handledAlerts([alert(gmailAlert)]) == ["a"])
    }

    @Test func mailMissingFromACopyThatHasntCaughtUpKeepsItsAlert() {
        let own = snapshot([row(gmail, "t0", minutesAfter: -60)], minutesAfter: 5)
        #expect(mailbox(phone: snapshot([]), own: own).handledAlerts([alert(gmailAlert)]).isEmpty)
    }

    @Test func mailMissingFromAFullListOfNewerMailKeepsItsAlert() {
        let rows = (0..<WristSnapshot.rowLimit).map { row(gmail, "n\($0)", minutesAfter: Double($0 + 1)) }
        #expect(mailbox(phone: snapshot([]), own: snapshot(rows)).handledAlerts([alert(gmailAlert)]).isEmpty)
    }

    @Test func anAlertForAnAccountTheWatchDoesntKnowStays() {
        let stranger = alert(["account": "someone@else.com", "threadID": "t1"])
        #expect(mailbox(phone: snapshot([]), own: snapshot([])).handledAlerts([stranger]).isEmpty)
    }
}
