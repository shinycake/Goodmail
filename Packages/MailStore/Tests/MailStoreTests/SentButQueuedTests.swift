import Foundation
import MailCore
import Synchronization
import Testing

@testable import MailStore

/// A message that went while its queue couldn't be written, as while the database is suspended, never goes again.
struct SentButQueuedTests {
    @Test func aSentMessageTheQueueCouldNotLetGoOfIsNotSentAgain() async throws {
        let bench = try SendBench(sendPath: .direct)
        let store = DequeueFailingStore(bench.database)
        let sender = Sender(
            accountID: bench.account, provider: { bench.server }, store: store, transport: bench.uploads,
            uploads: bench.uploadsDirectory, now: bench.clock.next)
        try await bench.commands().send(bench.draft("First"), after: .zero)
        try await bench.commands().send(bench.draft("Second"), after: .zero)

        store.failing(true)
        #expect(await sender.flush().map(\.subject) == ["First"], "it went, and the drain stopped there")
        #expect(await sender.flush().isEmpty, "the queue still can't be written, so nothing more goes")
        #expect(bench.server.sent.count == 1)

        store.failing(false)
        #expect(await sender.flush().map(\.subject) == ["Second"])
        #expect(bench.server.sent.count == 2, "First went once")
        #expect(try bench.database.dueMessages(for: bench.account, by: .distantFuture).isEmpty)
    }
}

/// The database as an outgoing store whose writes taking a message out of the queue throw while `failing` is on.
private final class DequeueFailingStore: OutgoingStore {
    private let database: MailDatabase
    private let isFailing = Mutex(false)

    init(_ database: MailDatabase) { self.database = database }

    func failing(_ on: Bool) { isFailing.withLock { $0 = on } }

    func update(_ id: Draft.ID, from expected: OutgoingMessage.Delivery, to message: OutgoingMessage?) throws -> Bool {
        if message == nil, isFailing.withLock({ $0 }) { throw CancellationError() }
        return try database.update(id, from: expected, to: message)
    }

    func enqueue(_ message: OutgoingMessage) throws { try database.enqueue(message) }
    func enqueueSave(_ message: OutgoingMessage) throws { try database.enqueueSave(message) }
    func finish(_ message: OutgoingMessage) throws -> Bool { try database.finish(message) }
    func savedCopy(of draft: Draft.ID) throws -> Message.ID? { try database.savedCopy(of: draft) }
    func setSavedCopy(_ copy: Message.ID?, of draft: Draft.ID) throws { try database.setSavedCopy(copy, of: draft) }
    func cancel(_ id: Draft.ID) throws -> OutgoingMessage? { try database.cancel(id) }
    func requeue(_ id: Draft.ID, as purpose: OutgoingMessage.Purpose, at date: Date) throws -> OutgoingMessage? {
        try database.requeue(id, as: purpose, at: date)
    }
    func dueMessages(for account: AccountID, by date: Date) throws -> [OutgoingMessage] {
        try database.dueMessages(for: account, by: date)
    }
    func uploadingMessages(for account: AccountID) throws -> [OutgoingMessage] {
        try database.uploadingMessages(for: account)
    }
    func remove(_ id: Draft.ID) throws { try database.remove(id) }
    func sender(for account: AccountID) throws -> Contact { try database.sender(for: account) }
}
