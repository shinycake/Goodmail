import Foundation
import MailCore
import Testing

@testable import MailWrist

/// The watch keeps its mailbox across launches.
struct WristStoreTests {
    private let directory = FileManager.default.temporaryDirectory.appending(
        path: "WristStoreTests-\(UUID().uuidString)")

    @Test func startsEmpty() async {
        #expect(await WristStore(directory: directory).load() == WristMailbox())
    }

    @Test func keepsWhatWasSaved() async throws {
        let snapshot = WristSnapshot(
            madeAt: Date(timeIntervalSince1970: 1_800_000_000),
            accounts: [WristAccount(id: AccountID(rawValue: "a1"), address: "me@example.com", color: .teal, unread: 0)],
            rows: [])
        let command = WristCommand(
            threads: [ThreadSummary.ID(accountID: AccountID(rawValue: "a1"), threadID: "t1")], kind: .archive,
            madeAt: Date(timeIntervalSince1970: 1_800_000_000))
        let mailbox = WristMailbox(snapshot: snapshot, pending: [command])

        try await WristStore(directory: directory).save(mailbox)
        #expect(await WristStore(directory: directory).load() == mailbox)
    }

    @Test func aFileItCantReadCountsAsEmpty() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: directory.appending(path: "wrist-mailbox.json"))
        #expect(await WristStore(directory: directory).load() == WristMailbox())
    }

    /// What this build can't read, as after going back to an older build, is set aside rather than overwritten by
    /// the next save, so the build that wrote it can still read it.
    @Test func aFileItCantReadIsKeptAside() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let unreadable = Data("not json".utf8)
        try unreadable.write(to: directory.appending(path: "wrist-mailbox.json"))
        let store = WristStore(directory: directory)

        _ = await store.load()
        try await store.save(WristMailbox())

        #expect(try Data(contentsOf: directory.appending(path: "wrist-mailbox.unreadable.json")) == unreadable)
    }
}
