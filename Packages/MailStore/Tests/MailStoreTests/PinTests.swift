import Foundation
import MailCore
import Testing

@testable import MailStore

/// A pinned thread stays pinned on the device, whatever the provider does, until it is unpinned; undo takes a pin
/// back.
struct PinTests {
    private let database: MailDatabase
    private let account = Account(
        id: AccountID(rawValue: "a1"), email: "tester@example.com", color: .teal, service: .icloud)

    init() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "PinTests-\(UUID().uuidString)")
            .appending(path: "mail.sqlite")
        database = try MailDatabase(url: url)
        try database.save(account)
    }

    private func id(_ threadID: String) -> ThreadSummary.ID {
        ThreadSummary.ID(accountID: account.id, threadID: threadID)
    }

    private var commands: MailCommands { MailCommands(store: database, replay: { _ in }) }

    private func pinned() async throws -> Set<ThreadSummary.ID> {
        var pins = database.pinnedThreads().makeAsyncIterator()
        return try await pins.next() ?? []
    }

    @Test func pinningIsKeptUntilUnpinned() async throws {
        try await commands.pin([id("t1"), id("t2")], true)
        #expect(try await pinned() == [id("t1"), id("t2")])
        #expect(try database.pins(among: [id("t1"), id("t3")]) == [id("t1")])

        try await commands.pin([id("t1")], false)
        #expect(try await pinned() == [id("t2")])
    }

    @Test func undoPutsBackOnlyWhatChanged() async throws {
        let commands = commands
        try await commands.pin([id("t1")], true)
        let undo = try await commands.pin([id("t1"), id("t2")], true)
        #expect(undo.pins == [id("t2"): false], "t1 was pinned already")

        try await commands.undo(undo)
        #expect(try await pinned() == [id("t1")])
    }

    @Test func pinningQueuesNothingForTheProvider() async throws {
        try await commands.pin([id("t1")], true)
        #expect(try database.pendingIntents(for: account.id).isEmpty)
    }

    @Test func removingTheAccountForgetsItsPins() async throws {
        try await commands.pin([id("t1")], true)
        try database.removeAccount(account.id)
        #expect(try await pinned().isEmpty)
    }
}
