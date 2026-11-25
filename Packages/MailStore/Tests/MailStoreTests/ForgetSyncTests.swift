import Foundation
import MailCore
import Testing

@testable import MailStore

/// A copy that fell out of date forgets its cursor, its queued changes and its messages on their way, and keeps the
/// account and its threads.
struct ForgetSyncTests {
    private let database: MailDatabase
    private let account = Account(id: AccountID(rawValue: "a1"), email: "me@gmail.com", color: .teal, service: .gmail)
    private let other = Account(id: AccountID(rawValue: "a2"), email: "me@outlook.com", color: .blue, service: .outlook)
    private static let date = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        database = try MailDatabase(
            url: FileManager.default.temporaryDirectory.appending(path: "ForgetSyncTests-\(UUID().uuidString)")
                .appending(path: "mail.sqlite"))
        try database.save(account)
        try database.save(other)
    }

    @Test func theCursorAndQueueGoAndTheThreadsStay() throws {
        let threads = try seedThreads()
        for id in [account.id, other.id] {
            try database.apply(StoreChanges(accountID: id, progress: .current(cursor: "7")))
            _ = try database.enqueue(
                [OutboxIntent(threadID: "t1", action: .archive, createdAt: Self.date)], account: id)
            try database.enqueue(
                OutgoingMessage(
                    draft: Draft(accountID: id, subject: "Re: Lunch?", body: MessageBody(plain: "Yes")),
                    sendAt: Self.date, delivery: .uploading(UploadID())))
        }

        try database.forgetSync(of: account.id)

        #expect(try database.syncState(for: account.id) == nil)
        #expect(try database.pendingIntents(for: account.id).isEmpty)
        #expect(try database.uploadingMessages(for: account.id).isEmpty)
        #expect(Set(try database.accounts().map(\.id)) == [account.id, other.id])
        #expect(try database.thread(threads[0].id) != nil)
        #expect(try database.syncState(for: other.id) == .current(cursor: "7"), "other accounts keep theirs")
        #expect(try database.pendingIntents(for: other.id).count == 1)
        #expect(try database.uploadingMessages(for: other.id).count == 1)
    }

    /// Stores a thread "t1" in each account, for intents to queue on.
    private func seedThreads() throws -> [ThreadSummary] {
        let threads = [account.id, other.id].map { id in
            ThreadSummary(
                id: ThreadSummary.ID(accountID: id, threadID: "t1"), subject: "Lunch?", snippet: "",
                sender: Contact(name: nil, address: "a@example.com"), date: Self.date, isUnread: true,
                messageCount: 1, labelIDs: ["INBOX"])
        }
        try database.upsert(threads)
        return threads
    }

    @Test func aWatchChangeIsKeptUntilNothingOfItIsOnItsWay() throws {
        _ = try seedThreads()
        let (archive, reply) = (UUID(), UUID())
        let draft = Draft(accountID: account.id, subject: "Re: Lunch?", threadID: "t1")
        try database.keepWatchChange(archive, command: Data("archive".utf8))
        try database.keepWatchChange(reply, command: Data("reply".utf8))
        try database.keepWatchChange(archive, command: Data("again".utf8))
        _ = try database.enqueue(
            [OutboxIntent(threadID: "t1", action: .archive, createdAt: Self.date, origin: archive)], account: account.id
        )
        try database.addDraft(draft.id, toWatchChange: reply)
        try database.enqueue(OutgoingMessage(draft: draft, sendAt: Self.date))

        #expect(
            try database.watchChanges() == [
                WatchChange(id: archive, command: Data("archive".utf8), queued: true),
                WatchChange(id: reply, command: Data("reply".utf8), drafts: [draft.id]),
            ])
        try database.removeSettledWatchChanges(except: [])
        #expect(try database.watchChanges().count == 2, "both still on their way")

        let intent = try #require(try database.pendingIntents(for: account.id).first)
        #expect(intent.origin == archive, "read back from beside the intent")
        try database.markSent(intent.id, at: Self.date)
        try database.remove(draft.id)
        try database.removeSettledWatchChanges(except: [reply])
        #expect(try database.watchChanges().map(\.id) == [reply], "the one still being made stays")
        try database.removeWatchChange(reply)
        #expect(try database.watchChanges().isEmpty)
    }

    @Test func aHandOverKeepsWhatItGivesBackAndForgetsTheCopyAtOnce() throws {
        _ = try seedThreads()
        let change = UUID()
        try database.keepWatchChange(change, command: Data("archive".utf8))
        for id in [account.id, other.id] {
            _ = try database.enqueue(
                [OutboxIntent(threadID: "t1", action: .archive, createdAt: Self.date, origin: change)], account: id)
        }

        try database.handOver([Data("first".utf8), Data("second".utf8)], changes: [change])

        #expect(try database.watchChanges().isEmpty)
        #expect(try database.pendingIntents(for: account.id).isEmpty)
        #expect(try database.pendingIntents(for: other.id).isEmpty)
        let kept = try database.watchHandbacks()
        #expect(kept.map(\.handback) == [Data("first".utf8), Data("second".utf8)])
        try database.removeWatchHandbacks([kept[0].position])
        #expect(try database.watchHandbacks().map(\.handback) == [Data("second".utf8)])
    }
}
