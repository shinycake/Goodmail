import Foundation
import MailCore
import MailStore
import Testing

@testable import MailNotifications

struct NewMailAlertTests {
    private let account = Account(id: AccountID(rawValue: "a1"), email: "me@example.com", color: .teal, service: .gmail)

    private func thread(subject: String = "Lunch?") -> ThreadSummary {
        ThreadSummary(
            id: ThreadSummary.ID(accountID: account.id, threadID: "t1"), subject: subject, snippet: "Tomorrow at one",
            sender: Contact(name: "Dana Levi", address: "dana@example.com"), date: .now, isUnread: true,
            messageCount: 1, labelIDs: [SystemLabel.inbox])
    }

    @Test func theAlertShowsTheSenderSubjectAndPreviewStackedByAccount() {
        let content = NewMailAlert.content(for: thread(), in: account)
        #expect(content.title == "Dana Levi")
        #expect(content.subtitle == "Lunch?")
        #expect(content.body == "Tomorrow at one")
        #expect(content.threadIdentifier == "a1")
        #expect(content.categoryIdentifier == NewMailAlert.categoryID)
    }

    @Test func mailWithoutASubjectSaysSo() {
        #expect(NewMailAlert.content(for: thread(subject: ""), in: account).subtitle == "No Subject")
    }

    @Test func aTapNamesTheThreadItAlertedFor() {
        let content = NewMailAlert.content(for: thread(), in: account)
        #expect(NewMailAlert.thread(in: content.userInfo) == ThreadSummary.ID(accountID: account.id, threadID: "t1"))
        #expect(NewMailAlert.thread(in: ["account": "me@example.com", "historyId": "9"]) == nil)
    }

    @Test func theActionsPutTrashLastAsDestructive() {
        let actions = NewMailAlert.category.actions
        #expect(actions.map(\.identifier) == NewMailAlert.Action.allCases.map(\.rawValue))
        #expect(actions.last?.options.contains(.destructive) == true)
    }
}

struct NewMailFetchTests {
    private let database: MailDatabase
    private let account = Account(id: AccountID(rawValue: "a1"), email: "Me@Example.com", color: .teal, service: .gmail)
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "NewMailFetchTests-\(UUID().uuidString)").appending(path: "mail.sqlite")
        database = try MailDatabase(url: url)
        try database.save(account)
        try database.apply(StoreChanges(accountID: account.id, state: .current(cursor: "1")))
    }

    private func fetch(_ provider: ChangedThreads) -> NewMailFetch {
        NewMailFetch(database: database, provider: { _ in provider }, now: { [now] in now })
    }

    private func thread(_ id: String, unread: Bool = true) -> ThreadSummary {
        ThreadSummary(
            id: ThreadSummary.ID(accountID: account.id, threadID: id), subject: id, snippet: "",
            sender: Contact(name: nil, address: "dana@example.com"), date: now, isUnread: unread, messageCount: 1,
            labelIDs: [SystemLabel.inbox])
    }

    @Test func newMailAlertsOnceAndIsStored() async throws {
        let provider = ChangedThreads([thread("t1")])
        let first = try await fetch(provider).run(address: "me@example.com")
        #expect(first == .alerts([thread("t1")], in: account))
        #expect(try await fetch(provider).run(address: "me@example.com") == .nothingNew)
    }

    @Test func aReadChangeAlertsForNothing() async throws {
        #expect(
            try await fetch(ChangedThreads([thread("t1", unread: false)])).run(address: account.email) == .nothingNew)
    }

    @Test func turningAlertsOffSilencesThem() async throws {
        try database.setNotificationLevel(.off, for: account.id, now: now)
        #expect(try await fetch(ChangedThreads([thread("t1")])).run(address: account.email) == .nothingNew)
    }

    @Test func anAddressNotOnTheDeviceIsAnError() async throws {
        await #expect(throws: NewMailFetch.Failure.unknownAccount) {
            try await fetch(ChangedThreads([])).run(address: "someone@example.com")
        }
    }
}

/// A provider whose every change set holds `threads`.
private struct ChangedThreads: MailProvider {
    let threads: [ThreadSummary]

    init(_ threads: [ThreadSummary]) {
        self.threads = threads
    }

    func changes(since cursor: String) async throws -> ChangeSet {
        ChangeSet(threadIDs: Set(threads.map(\.id.threadID)), cursor: "2")
    }
    func threads(withIDs ids: [String]) async throws -> ThreadFetch { ThreadFetch(found: threads, missing: []) }

    func labels() async throws -> [MailLabel] { [] }
    func currentCursor() async throws -> String { "2" }
    func threads(matching query: ThreadQuery, pageToken: String?) async throws -> ThreadPage {
        ThreadPage(threads: [], nextPageToken: nil)
    }
    func messages(inThread threadID: String) async throws -> [Message] { [] }
    func data(for attachment: MailCore.Attachment, in message: Message.ID) async throws -> Data { Data() }
    func perform(_ action: ThreadAction, onThread threadID: String) async throws {}
    var sending: Sending { .direct { _, _ in } }
    func saveDraft(_ raw: Data, inThread threadID: String?, replacing: Message.ID?) async throws {}
    func deleteDraft(_ message: Message.ID) async throws {}
    func contacts() async throws -> [Contact] { [] }
    func signature() async throws -> String { "" }
}
