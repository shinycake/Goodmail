import Foundation
import MailCore
import Testing

@testable import MailStore

// Follows a store stream, so one that never emits fails the test instead of hanging the run.
@Suite(.timeLimit(.minutes(1)))
struct ThreadLabelsStoreTests {
    private let database: MailDatabase
    private let account = Account(
        id: AccountID(rawValue: "a1"), email: "tester@example.com", color: .teal, service: .gmail)
    private var thread: ThreadSummary {
        ThreadSummary(
            id: ThreadSummary.ID(accountID: account.id, threadID: "t1"), subject: "s", snippet: "",
            sender: Contact(name: nil, address: "a@example.com"), date: .now, isUnread: false, messageCount: 1,
            labelIDs: [SystemLabel.inbox])
    }

    init() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "ThreadLabelsStoreTests-\(UUID().uuidString)")
            .appending(path: "mail.sqlite")
        database = try MailDatabase(url: url)
        try database.save(account)
    }

    @Test func followsTheThreadsRowAsSyncChangesIt() async throws {
        try database.upsert([thread])
        var labels = database.labels(ofThread: thread.id).makeAsyncIterator()
        #expect(try await labels.next(isolation: #isolation) == [SystemLabel.inbox])
        // Archived on another device: sync rewrites the row and its labels, not the cached messages.
        var archived = thread
        archived.labelIDs = [SystemLabel.starred]
        try database.upsert([archived])
        #expect(try await labels.next(isolation: #isolation) == [SystemLabel.starred])
    }

    @Test func aThreadNotOnTheDeviceHasNoLabels() async throws {
        var labels = database.labels(ofThread: thread.id).makeAsyncIterator()
        let first = try await labels.next(isolation: #isolation)
        #expect(first == .some(nil))
    }
}
