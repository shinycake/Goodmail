import Foundation
import MailCore
import Synchronization
import Testing

@testable import MailStore

/// A queue that can't be read or written, as while the database is suspended, stops what depends on it and says so in
/// the log, instead of taking a failed read for an empty queue or trying a step it can't record again and again.
@Suite(.timeLimit(.minutes(1)))
struct QueueFailureTests {
    private let entries = Entries()

    private func sender(on bench: SendBench, store: FailingStore) -> Sender {
        Sender(
            accountID: bench.account, provider: { bench.server }, store: store, transport: bench.uploads,
            uploads: bench.uploadsDirectory, now: bench.clock.next, log: entries.log)
    }

    @Test func aQueueThatCantBeReadSendsNothingUntilItCan() async throws {
        let bench = try SendBench(sendPath: .direct)
        let store = FailingStore(bench.database)
        let sender = sender(on: bench, store: store)
        try await bench.commands().send(bench.draft(), after: .zero)

        store.fail(.reads)
        #expect(await sender.flush().isEmpty)
        #expect(bench.server.sent.isEmpty)
        #expect(entries.levels == [.error])

        store.fail(.nothing)
        #expect(await sender.flush().map(\.subject) == ["Hello"])
    }

    @Test func aRefusalTheQueueCantRecordStopsTheDrain() async throws {
        let bench = try SendBench(sendPath: .direct)
        let store = FailingStore(bench.database)
        let sender = sender(on: bench, store: store)
        bench.server.answerSends(with: 400)
        try await bench.commands().send(bench.draft(), after: .zero)

        store.fail(.writes)
        #expect(await sender.flush().isEmpty, "it stops, rather than sending the message again")
        #expect(bench.server.sendAttempts == 1)
        #expect(entries.levels == [.error])

        store.fail(.nothing)
        await sender.flush()
        #expect(try await bench.failures() == [.rejected])
    }

    @Test func aSentMessageTheQueueCantLetGoOfIsAFault() async throws {
        let bench = try SendBench(sendPath: .direct)
        let store = FailingStore(bench.database)
        let sender = sender(on: bench, store: store)
        try await bench.commands().send(bench.draft(), after: .zero)

        store.fail(.writes)
        #expect(await sender.flush().map(\.subject) == ["Hello"])
        #expect(entries.levels == [.fault])
        #expect(bench.server.sent.count == 1)
    }

    @Test func anUploadKeepsItsFileWhileTheQueueCantBeRead() async throws {
        let bench = try SendBench()
        let store = FailingStore(bench.database)
        let sender = sender(on: bench, store: store)
        try await bench.commands().send(bench.draft(), after: .zero)
        await sender.flush()
        #expect(bench.uploadFiles().count == 1)

        store.fail(.reads)
        await sender.flush()
        #expect(bench.uploadFiles().count == 1, "an unread queue says nothing about which files are needed")
        #expect(entries.levels.contains(.error))

        store.fail(.nothing)
        #expect(try await bench.deliver(with: sender).map(\.subject) == ["Hello"])
    }

    @Test func anUploadKeepsItsFileWhenOnlyTheReadAfterSettlingFails() async throws {
        let bench = try SendBench()
        let store = FailingStore(bench.database)
        let sender = sender(on: bench, store: store)
        try await bench.commands().send(bench.draft(), after: .zero)
        await sender.flush()
        #expect(bench.uploadFiles().count == 1)

        // Settling reads the uploads under way; the read that says which files to keep is the one that fails.
        store.fail(.uploadingReads(after: 1))
        await sender.flush()
        #expect(bench.uploadFiles().count == 1, "an unread queue says nothing about which files are needed")
        #expect(entries.levels == [.error])

        store.fail(.nothing)
        #expect(try await bench.deliver(with: sender).map(\.subject) == ["Hello"])
    }

    @Test func aDraftTheQueueCantKeepIsLogged() async throws {
        let bench = try SendBench()
        let store = FailingStore(bench.database)
        let keeper = DraftKeeper(store: store, log: entries.log)
        store.fail(.writes)
        keeper.keep(.written(bench.draft(), by: .distantFuture))
        await keeper.settle()

        #expect(entries.levels == [.error])
        #expect(try bench.database.dueMessages(for: bench.account, by: .distantFuture).isEmpty)
    }
}

/// Records what a log was given.
private final class Entries: Sendable {
    private let entries = Mutex<[MailLog.Entry]>([])

    var log: MailLog {
        MailLog(category: "test") { [self] entry in entries.withLock { $0.append(entry) } }
    }

    var levels: [MailLog.Level] { entries.withLock { $0.map(\.level) } }
}

/// The database as an outgoing store whose reads or writes throw, as a suspended database's do.
private final class FailingStore: OutgoingStore {
    enum Failing: Equatable {
        case nothing
        /// Reads of the queue and of the account throw.
        case reads
        /// Every change to the queue throws.
        case writes
        /// Reads of the uploads under way go through `after` more times, then throw.
        case uploadingReads(after: Int)
    }

    private struct Suspended: Error {}

    private let database: MailDatabase
    private let failing = Mutex(Failing.nothing)

    init(_ database: MailDatabase) { self.database = database }

    func fail(_ what: Failing) { failing.withLock { $0 = what } }

    private func reading<T>(_ read: () throws -> T) throws -> T {
        if failing.withLock({ $0 }) == .reads { throw Suspended() }
        return try read()
    }

    private func writing<T>(_ write: () throws -> T) throws -> T {
        if failing.withLock({ $0 }) == .writes { throw Suspended() }
        return try write()
    }

    func enqueue(_ message: OutgoingMessage) throws { try writing { try database.enqueue(message) } }
    func enqueueSave(_ message: OutgoingMessage) throws { try writing { try database.enqueueSave(message) } }
    func finish(_ message: OutgoingMessage) throws -> Bool { try writing { try database.finish(message) } }
    func savedCopy(of draft: Draft.ID) throws -> Message.ID? { try reading { try database.savedCopy(of: draft) } }
    func setSavedCopy(_ copy: Message.ID?, of draft: Draft.ID) throws {
        try writing { try database.setSavedCopy(copy, of: draft) }
    }
    func cancel(_ id: Draft.ID) throws -> OutgoingMessage? { try writing { try database.cancel(id) } }
    func requeue(_ id: Draft.ID, as purpose: OutgoingMessage.Purpose, at date: Date) throws -> OutgoingMessage? {
        try writing { try database.requeue(id, as: purpose, at: date) }
    }
    func dueMessages(for account: AccountID, by date: Date) throws -> [OutgoingMessage] {
        try reading { try database.dueMessages(for: account, by: date) }
    }
    func uploadingMessages(for account: AccountID) throws -> [OutgoingMessage] {
        let fails = failing.withLock { failing in
            guard case .uploadingReads(let after) = failing else { return failing == .reads }
            failing = .uploadingReads(after: max(0, after - 1))
            return after == 0
        }
        if fails { throw Suspended() }
        return try database.uploadingMessages(for: account)
    }
    func update(_ id: Draft.ID, from expected: OutgoingMessage.Delivery, to message: OutgoingMessage?) throws -> Bool {
        try writing { try database.update(id, from: expected, to: message) }
    }
    func remove(_ id: Draft.ID) throws { try writing { try database.remove(id) } }
    func sender(for account: AccountID) throws -> Contact { try reading { try database.sender(for: account) } }
}
