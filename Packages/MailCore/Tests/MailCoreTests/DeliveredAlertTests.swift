import Foundation
import MailCore
import Testing

/// Which thread a delivered alert is about, and why it alerted, from what iOS hands back.
struct DeliveredAlertTests {
    private let gmail = Account(id: AccountID(rawValue: "g1"), email: "Me@Gmail.com", color: .teal, service: .gmail)
    private let at = Date(timeIntervalSince1970: 1_800_000_000)
    private let outlook = Account(
        id: AccountID(rawValue: "o1"), email: "me@outlook.com", color: .blue, service: .outlook)

    @Test func theAppsOwnAlertIsForNewMail() throws {
        let thread = ThreadSummary.ID(accountID: gmail.id, threadID: "t1")
        let alert = try #require(
            DeliveredAlert(
                identifier: "g1/t1", userInfo: AlertedThread.userInfo(for: thread), deliveredAt: at, accounts: [gmail]))
        #expect(alert == DeliveredAlert(identifier: "g1/t1", thread: thread, kind: .newMail, deliveredAt: at))
    }

    @Test func aRulesNotificationIsTheRules() throws {
        let thread = ThreadSummary.ID(accountID: gmail.id, threadID: "t1")
        let alert = try #require(
            DeliveredAlert(
                identifier: "rule/r1/g1/t1", userInfo: AlertedThread.userInfo(for: thread), deliveredAt: at,
                accounts: [gmail]))
        #expect(alert.kind == .rule)
    }

    @Test func anOutlookPushShownAsSentNamesItsConversation() throws {
        let payload: [AnyHashable: Any] = [
            "aps": ["alert": ["title": "Dana"]], "accountID": "o1", "threadID": "c1", "alert": "a-1",
        ]
        let alert = try #require(
            DeliveredAlert(identifier: "a-1", userInfo: payload, deliveredAt: at, accounts: [outlook]))
        #expect(alert.thread == ThreadSummary.ID(accountID: outlook.id, threadID: "c1"))
        #expect(alert.kind == .relayed)
    }

    @Test func aGmailPushShownAsSentFindsItsAccountByAddress() throws {
        let payload: [AnyHashable: Any] = [
            "aps": ["alert": ["title": "Dana"]], "account": "me@gmail.com", "historyId": "9", "threadID": "t9",
        ]
        let alert = try #require(
            DeliveredAlert(identifier: "x", userInfo: payload, deliveredAt: at, accounts: [outlook, gmail]))
        #expect(alert.thread == ThreadSummary.ID(accountID: gmail.id, threadID: "t9"))
        #expect(alert.kind == .relayed)
    }

    @Test func anotherFeaturesAlertAboutAThreadIsLeftAlone() {
        let thread = ThreadSummary.ID(accountID: gmail.id, threadID: "t1")
        let snooze = DeliveredAlert(
            identifier: "snooze/g1/t1", userInfo: AlertedThread.userInfo(for: thread), deliveredAt: at,
            accounts: [gmail])
        #expect(snooze == nil)
    }

    @Test func theAlertTheExtensionHandsIOSForAPushIsNewMail() throws {
        let thread = ThreadSummary.ID(accountID: gmail.id, threadID: "t1")
        let alert = try #require(
            DeliveredAlert(
                identifier: "0C4F9D2E-6B1A-4E39-9A61-3F2B8D7C5E10", userInfo: AlertedThread.userInfo(for: thread),
                deliveredAt: at, accounts: [gmail]))
        #expect(alert.kind == .newMail)
    }

    @Test func anAlertThatNamesNoKnownThreadIsLeftAlone() {
        let payloads: [[AnyHashable: Any]] = [
            // An IMAP push names only its account.
            ["aps": ["alert": ["title": "Dana"]], "accountID": "i1", "alert": "a-2"],
            ["aps": ["alert": ["title": "Dana"]], "account": "someone@else.com", "threadID": "t1"],
            ["aps": ["alert": ["title": "Dana"]], "account": "me@gmail.com", "threadID": ""],
            // Nothing to name a thread.
            [:],
        ]
        for payload in payloads {
            #expect(
                DeliveredAlert(identifier: "x", userInfo: payload, deliveredAt: at, accounts: [gmail, outlook]) == nil)
        }
    }
}
