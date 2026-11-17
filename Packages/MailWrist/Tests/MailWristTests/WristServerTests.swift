import Foundation
import MailCore
import Synchronization
import Testing

@testable import MailWrist

/// The iPhone runs each of the watch's commands once and tells the watch which it ran.
struct WristServerTests {
    /// What the server did, in order.
    private final class Log: Sendable {
        let executed = Mutex<[WristCommand]>([])
        let sent = Mutex<[WristSnapshot]>([])
        let remembered = Mutex<[UUID]>([])
    }

    private struct Refused: Error {}

    private let log = Log()
    private let snapshot = WristSnapshot(madeAt: Date(timeIntervalSince1970: 1_800_000_000), accounts: [], rows: [])

    private func command(_ kind: WristCommand.Kind = .archive) -> WristCommand {
        WristCommand(
            threads: [ThreadSummary.ID(accountID: AccountID(rawValue: "a1"), threadID: "t1")], kind: kind,
            madeAt: Date(timeIntervalSince1970: 1_800_000_000))
    }

    private func server(applied: [UUID] = [], failing: Bool = false) -> WristServer {
        WristServer(
            applied: applied,
            execute: { [log] command in
                log.executed.withLock { $0.append(command) }
                if failing { throw Refused() }
            },
            send: { [log] snapshot in log.sent.withLock { $0.append(snapshot) } },
            remember: { [log] applied in log.remembered.withLock { $0 = applied } })
    }

    @Test func sendsEachInboxChange() async {
        let server = server()
        await server.inboxChanged(snapshot)
        #expect(log.sent.withLock { $0 } == [snapshot])
    }

    @Test func runsACommandOnceAndListsItAsApplied() async throws {
        let server = server()
        await server.inboxChanged(snapshot)
        let archive = command()

        try await server.received(archive)
        try await server.received(archive)

        #expect(log.executed.withLock { $0 } == [archive])
        #expect(log.remembered.withLock { $0 } == [archive.id])
        #expect(log.sent.withLock { $0.count } == 1, "The Inbox from before the archive confirms nothing")

        await server.inboxChanged(snapshot)
        #expect(log.sent.withLock { $0.last?.applied } == [archive.id])
    }

    @Test func remembersAcrossLaunches() async throws {
        let archive = command()
        try await server(applied: [archive.id]).received(archive)
        #expect(log.executed.withLock { $0 }.isEmpty)
    }

    @Test func aFailedCommandCountsAsRunAndThrows() async {
        let server = server(failing: true)
        await server.inboxChanged(snapshot)
        let archive = command()

        await #expect(throws: Refused.self) { try await server.received(archive) }
        #expect(log.sent.withLock { $0.last?.applied } == [archive.id])
    }

    @Test func keepsOnlyTheNewestApplied() async throws {
        let server = server()
        let commands = (0..<(WristServer.appliedLimit + 3)).map { _ in command(.markRead(true)) }
        for command in commands { try await server.received(command) }
        #expect(log.remembered.withLock { $0 } == commands.suffix(WristServer.appliedLimit).map(\.id))
    }

    @Test(arguments: [
        (WristCommand.Kind.archive, ThreadAction.archive), (.moveToInbox, .moveToInbox), (.trash, .trash),
        (.untrash, .untrash), (.markRead(true), .markRead(true)), (.markRead(false), .markRead(false)),
    ])
    func eachMailChangeIsTheIPhonesAction(kind: WristCommand.Kind, action: ThreadAction) {
        #expect(kind.threadAction == action)
    }

    @Test func aPinIsNoMailAction() {
        #expect(WristCommand.Kind.pin(true).threadAction == nil)
        #expect(WristCommand.Kind.reply("Thanks!").threadAction == nil)
    }
}
