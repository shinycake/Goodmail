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

    /// Holds each run until the test lets it finish, and says when one has started.
    private struct Gate: Sendable {
        let started: AsyncStream<Void>
        let startedIn: AsyncStream<Void>.Continuation
        let finish: AsyncStream<Void>
        let finishIn: AsyncStream<Void>.Continuation

        init() {
            (started, startedIn) = AsyncStream.makeStream()
            (finish, finishIn) = AsyncStream.makeStream()
        }

        func pass() async {
            startedIn.yield()
            var finishing = finish.makeAsyncIterator()
            _ = await finishing.next()
        }
    }

    private func server(applied: [UUID] = [], failing: Bool = false, gate: Gate? = nil) -> WristServer {
        WristServer(
            applied: applied,
            execute: { [log] command in
                log.executed.withLock { $0.append(command) }
                await gate?.pass()
                if failing { throw Refused() }
            },
            send: { [log] snapshot in log.sent.withLock { $0.append(snapshot) } },
            remember: { [log] applied in log.remembered.withLock { $0 = applied } })
    }

    @Test func listsAFailedCommandAsFailed() async {
        let server = server(failing: true)
        await server.inboxChanged(snapshot)
        let reply = command(.reply("Thanks!"))
        await #expect(throws: Refused.self) { try await server.received(reply) }
        let sent = log.sent.withLock { $0.last }
        #expect(sent?.applied == [reply.id])
        #expect(sent?.failed == [reply.id])
    }

    @Test func sendsEachInboxChange() async {
        let server = server()
        await server.inboxChanged(snapshot)
        #expect(log.sent.withLock { $0 } == [snapshot])
    }

    @Test func theSwitchReachesTheWatchWithoutWaitingForMail() async {
        let server = server()
        var withExtras = snapshot
        withExtras.extras = WristExtras(independence: .on)
        await server.inboxChanged(withExtras)
        let later = Date(timeIntervalSince1970: 1_800_000_060)

        await server.independenceChanged(to: .off, at: later)

        let sent = log.sent.withLock { $0.last }
        #expect(sent?.extras?.independence == .off)
        #expect(sent?.madeAt == later)
        #expect(sent?.rows == withExtras.rows)
    }

    @Test func anIPhoneWithoutExtrasHasNoSwitchToSend() async {
        let server = server()
        await server.independenceChanged(to: .off, at: .now)
        await server.inboxChanged(snapshot)
        await server.independenceChanged(to: .off, at: .now)
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

    /// The Inbox can change while a command runs; that Inbox doesn't confirm it, since the command may yet fail, and
    /// the command isn't stored as run, since the app may be stopped before it does.
    @Test func aCommandStillRunningIsNeitherConfirmedNorRemembered() async throws {
        let gate = Gate()
        let server = server(gate: gate)
        await server.inboxChanged(snapshot)
        let reply = command(.reply("Thanks!"))
        async let running: Void = server.received(reply)
        var started = gate.started.makeAsyncIterator()
        await started.next()

        await server.inboxChanged(snapshot)
        try await server.received(reply)

        #expect(log.sent.withLock { $0.last?.applied } == [])
        #expect(log.remembered.withLock { $0 }.isEmpty)
        gate.finishIn.yield()
        try await running
        #expect(log.executed.withLock { $0 } == [reply], "Received again while running, it still runs once")
        #expect(log.remembered.withLock { $0 } == [reply.id])
    }

    /// The Inbox that changed while a command ran carries its effect, so it confirms the command once it is done.
    @Test func anInboxChangedDuringTheRunConfirmsItOnceDone() async throws {
        let gate = Gate()
        let server = server(gate: gate)
        await server.inboxChanged(snapshot)
        let archive = command()
        async let running: Void = server.received(archive)
        var started = gate.started.makeAsyncIterator()
        await started.next()
        await server.inboxChanged(snapshot)

        gate.finishIn.yield()
        try await running

        #expect(log.sent.withLock { $0.last?.applied } == [archive.id])
    }

    @Test func remembersAcrossLaunches() async throws {
        let archive = command()
        try await server(applied: [archive.id]).received(archive)
        #expect(log.executed.withLock { $0 }.isEmpty)
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
        #expect(WristCommand.Kind.snooze(until: .now).threadAction == nil)
    }
}
