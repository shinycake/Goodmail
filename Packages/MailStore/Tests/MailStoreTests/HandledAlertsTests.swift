import Foundation
import MailCore
import Testing

@testable import MailStore

/// An alert comes down once its mail is dealt with, as the store has it, however the change reached the store.
struct HandledAlertsTests {
    private let database: MailDatabase
    private let account = Account(id: AccountID(rawValue: "a1"), email: "me@example.com", color: .teal, service: .gmail)
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "HandledAlertsTests-\(UUID().uuidString)")
            .appending(path: "mail.sqlite")
        database = try MailDatabase(url: url)
        try database.save(account)
        try database.upsert([thread("waiting")])
    }

    private func thread(_ id: String, unread: Bool = true, labels: Set<String> = [SystemLabel.inbox]) -> ThreadSummary {
        ThreadSummary(
            id: ThreadSummary.ID(accountID: account.id, threadID: id), subject: "Hi", snippet: "",
            sender: Contact(name: nil, address: "dana@example.com"), date: now, isUnread: unread, messageCount: 1,
            labelIDs: labels)
    }

    private func alert(_ thread: String, _ kind: DeliveredAlert.Kind) -> DeliveredAlert {
        DeliveredAlert(
            identifier: "\(kind)/\(thread)", thread: ThreadSummary.ID(accountID: account.id, threadID: thread),
            kind: kind, deliveredAt: now)
    }

    @Test(arguments: [DeliveredAlert.Kind.newMail, .relayed, .rule])
    func unreadMailInTheInboxKeepsItsAlert(kind: DeliveredAlert.Kind) throws {
        #expect(try database.handledAlerts([alert("waiting", kind)]).isEmpty)
    }

    @Test(arguments: [DeliveredAlert.Kind.newMail, .relayed, .rule])
    func readMailTakesItsAlertDown(kind: DeliveredAlert.Kind) throws {
        try database.upsert([thread("waiting", unread: false)])
        #expect(try database.handledAlerts([alert("waiting", kind)]) == ["\(kind)/waiting"])
    }

    @Test func mailFiledOutOfTheInboxTakesItsNewMailAlertDown() throws {
        try database.upsert([thread("waiting", labels: ["Label_7"]), thread("trashed", labels: [SystemLabel.trash])])
        let alerts = [alert("waiting", .newMail), alert("trashed", .relayed)]
        #expect(try database.handledAlerts(alerts) == ["newMail/waiting", "relayed/trashed"])
    }

    @Test func aRulesNotificationStaysForMailTheRuleFiledUntilItIsReadOrDeleted() throws {
        try database.upsert([thread("filed", labels: ["Label_7"]), thread("spam", labels: [SystemLabel.spam])])
        #expect(try database.handledAlerts([alert("filed", .rule), alert("spam", .rule)]) == ["rule/spam"])
    }

    @Test func mailGoneFromTheStoreTakesDownAllButAPushWhoseMailIsntStoredYet() throws {
        let alerts = [alert("gone", .newMail), alert("gone", .rule), alert("gone", .relayed)]
        #expect(try database.handledAlerts(alerts) == ["newMail/gone", "rule/gone"])
    }

    @Test func aPushShownAsSentStaysWhileOnlyTheThreadAsItWasBeforeIsStored() throws {
        var before = thread("old", unread: false, labels: [])
        before.date = now.addingTimeInterval(-86_400)
        try database.upsert([before])
        #expect(try database.handledAlerts([alert("old", .relayed)]).isEmpty)
    }

    @Test func theMarkMovesWhenMailIsReadFiledOrDeletedAndNotForOtherSyncs() async throws {
        var marks = database.handlingChanges().makeAsyncIterator()
        let first = try #require(try await marks.next())
        try database.upsert([thread("waiting")])
        try database.upsert([thread("waiting", unread: false)])
        let read = try #require(try await marks.next())
        #expect(read != first)
        try database.upsert([thread("waiting", unread: false, labels: [SystemLabel.trash])])
        let trashed = try #require(try await marks.next())
        #expect(trashed != read)
        try database.apply(StoreChanges(accountID: account.id, deletions: ["waiting"]))
        #expect(try await marks.next() != trashed)
    }
}
