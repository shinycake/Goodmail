import Foundation
import MailCore
import Testing

@testable import MailIntents

struct ActionTests {
    private let host = FakeHost()
    private var catalog: Catalog { Catalog(host: host) }

    @Test func threadActionsGoThroughTheCommands() async throws {
        try await catalog.perform(.archive, onThreads: ["A1/t1", "A1/t2"])
        #expect(host.performed.on("t1") == [.archive])
        #expect(host.performed.on("t2") == [.archive])
    }

    @Test func anActionOnNothingStillOnTheDeviceFails() async {
        await #expect(throws: IntentError.self) { try await catalog.perform(.trash, onThreads: ["nonsense"]) }
    }

    @Test func messageActionsChangeTheirThreadsOnce() async throws {
        try await catalog.perform(.trash, onMessages: ["A1/t1/m1", "A1/t1/m2", "A1/t2/m3"])
        #expect(host.performed.on("t1") == [.trash])
        #expect(host.performed.on("t2") == [.trash])
    }

    @Test func updateMailTurnsEachGivenFlagIntoAnAction() {
        #expect(UpdateMailIntent.actions(isRead: nil, isFlagged: nil, isJunk: nil).isEmpty)
        #expect(
            UpdateMailIntent.actions(isRead: true, isFlagged: false, isJunk: true) == [
                .markRead(true), .star(false), .reportSpam,
            ])
        #expect(UpdateMailIntent.actions(isRead: nil, isFlagged: nil, isJunk: false).isEmpty)
    }

    @Test func anActionReturnsWhatUndoesIt() async throws {
        let change = try await catalog.perform(.archive, onThreads: ["A1/t1"])
        #expect(change.intents.values.joined().map(\.action) == [.archive])
    }

    @Test func undoTakesTheChangesBackNewestFirst() async throws {
        let read = try await catalog.perform(.markRead(true), onThreads: ["A1/t1"])
        let starred = try await catalog.perform(.star(true), onThreads: ["A1/t1"])
        try await IntentUndo.takeBack([read, MailCommands.Undo(), starred], through: host)
        #expect(
            host.performed.undone == [.star(true), .markRead(true)], "newest first, and nothing for an empty change")
    }

    @Test func notJunkUndoesNothingWhenNoMessageWasInJunk() async throws {
        #expect(try await catalog.markNotJunk([]).isEmpty)
    }
}
