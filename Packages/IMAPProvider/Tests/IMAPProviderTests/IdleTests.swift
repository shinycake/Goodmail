import Foundation
import MailCore
import Testing

@testable import IMAPProvider

/// One IDLE (RFC 2177) on a connection with the Inbox open.
struct IdleTests {
    static func connection(idling script: String) async throws -> (IMAPConnection, ScriptedTransport) {
        let transport = ScriptedTransport(
            transcript: """
                S: * PREAUTH [CAPABILITY IMAP4rev1 IDLE] ready
                \(IMAPClientTests.select("INBOX", tag: 1))
                C: A2 IDLE
                \(script)
                """)
        let connection = try await IMAPConnection(transport: transport, security: .tls)
        try await connection.select("INBOX")
        return (connection, transport)
    }

    @Test func newMailEndsTheIdle() async throws {
        let (connection, _) = try await Self.connection(
            idling: "S: + idling\nS: * 3 EXISTS\nC: DONE\nS: * 1 RECENT\nS: A2 OK IDLE terminated")
        #expect(try await connection.idle(renewingAfter: .seconds(3600)) == .changed)
        #expect(await connection.state.isSelected, "the mailbox stays open for the next IDLE")
    }

    @Test func aChangeReportedBeforeTheServerIdlesEndsTheIdleAtOnce() async throws {
        let (connection, _) = try await Self.connection(
            idling: "S: * 2 EXPUNGE\nS: + idling\nC: DONE\nS: A2 OK IDLE terminated")
        #expect(try await connection.idle(renewingAfter: .seconds(3600)) == .changed)
    }

    @Test func aQuietServerIsAskedAgainOnceTheRenewalComes() async throws {
        let (connection, transport) = try await Self.connection(
            idling: "S: + idling\nS: * OK Still here\n-- silent\nC: DONE\nS: A2 OK IDLE terminated")
        #expect(try await connection.idle(renewingAfter: .milliseconds(10)) == .renewal)
        #expect(await !transport.isClosed)
    }

    @Test func cancellingClosesTheConnection() async throws {
        let (connection, transport) = try await Self.connection(idling: "S: + idling\n-- silent")
        let idle = Task { try await connection.idle(renewingAfter: .seconds(3600)) }
        idle.cancel()
        await #expect(throws: CancellationError.self) { try await idle.value }
        #expect(await transport.isClosed)
        #expect(await connection.state == .closed)
    }

    @Test func aServerThatRefusesIdleLeavesTheMailboxOpen() async throws {
        let (connection, _) = try await Self.connection(idling: "S: A2 BAD unknown command")
        await #expect(throws: IMAPError.self) { try await connection.idle(renewingAfter: .seconds(3600)) }
        #expect(await connection.state.isSelected)
    }

    @Test(arguments: [
        ("* 4 EXISTS", true), ("* 2 EXPUNGE", true), (#"* 3 FETCH (UID 41 FLAGS (\Seen) MODSEQ (90211))"#, true),
        ("* VANISHED 41:42", true), ("* 1 RECENT", false), ("* FLAGS (\\Seen \\Flagged)", false),
    ])
    func whatCountsAsAChange(line: String, isChange: Bool) throws {
        guard case .data(let values) = try IMAPParser.response(from: Data((line + "\r\n").utf8)) else {
            Issue.record("not a data response")
            return
        }
        #expect(IMAPConnection.isChange(values) == isChange)
    }
}

extension IMAPConnection.State {
    var isSelected: Bool {
        guard case .selected = self else { return false }
        return true
    }
}
