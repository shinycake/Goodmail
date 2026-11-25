import Foundation
import MailCore
import Testing

@testable import IMAPProvider

/// What a server supports is unknown after STARTTLS and after login until it says again, and not knowing is never
/// taken as not supported: an EXPUNGE without UIDPLUS removes every message flagged `\Deleted`, not just the ones
/// asked for.
struct CapabilityTests {
    /// Logged in, as a sign-in leaves a connection, with nothing asked since.
    private static let loggedIn = """
        S: * OK [CAPABILITY IMAP4rev1 AUTH=PLAIN] ready
        C: A1 LOGIN "dana@example.com" "secret"
        S: A1 OK logged in
        C: A2 SELECT "Trash"
        S: * OK [UIDVALIDITY 7] ok
        S: A2 OK
        """

    private func loggedInConnection(_ transcript: String) async throws -> IMAPConnection {
        let transport = ScriptedTransport(transcript: Self.loggedIn + "\n" + transcript)
        let connection = try await IMAPConnection(transport: transport, security: .tls)
        try await connection.login(user: "dana@example.com", password: "secret")
        #expect(await connection.capabilities == .unknown, "the greeting's list is from before login")
        try await connection.select("Trash")
        return connection
    }

    @Test func anExpungeStraightAfterLoginAsksFirstAndNamesItsMessages() async throws {
        let connection = try await loggedInConnection(
            """
            C: A3 CAPABILITY
            S: * CAPABILITY IMAP4rev1 UIDPLUS
            S: A3 OK
            C: A4 UID STORE 5 +FLAGS.SILENT (\\Deleted)
            S: A4 OK
            C: A5 UID EXPUNGE 5
            S: A5 OK
            """)
        try await connection.expunge([5])
        #expect(await connection.capabilities == .known(["IMAP4REV1", "UIDPLUS"]))
    }

    @Test func aServerThatWontSayWhatItSupportsGetsNoExpunge() async throws {
        let connection = try await loggedInConnection(
            """
            C: A3 CAPABILITY
            S: A3 OK
            """)
        await #expect(throws: IMAPError.capabilitiesUnknown) { try await connection.expunge([5]) }
        #expect(await connection.capabilities == .unknown)
    }

    @Test func aServerThatListsItsCapabilitiesOnlyInTheOKIsBelieved() async throws {
        let connection = try await loggedInConnection(
            """
            C: A3 CAPABILITY
            S: A3 OK [CAPABILITY IMAP4rev1 UIDPLUS] done
            C: A4 UID STORE 5 +FLAGS.SILENT (\\Deleted)
            S: A4 OK
            C: A5 UID EXPUNGE 5
            S: A5 OK
            """)
        try await connection.expunge([5])
    }

    @Test func aRefusedMOVEAsksWhetherTheServerHasMOVEBeforeCopying() async throws {
        let connection = try await loggedInConnection(
            """
            C: A3 UID MOVE 5 "Archive"
            S: A3 BAD Unknown command
            C: A4 CAPABILITY
            S: * CAPABILITY IMAP4rev1 UIDPLUS
            S: A4 OK
            C: A5 UID COPY 5 "Archive"
            S: A5 OK [COPYUID 9 5 20] done
            C: A6 UID STORE 5 +FLAGS.SILENT (\\Deleted)
            S: A6 OK
            C: A7 UID EXPUNGE 5
            S: A7 OK
            """)
        let copy = try await connection.transfer([5], to: "Archive", move: true)
        #expect(copy?.uids == [5: 20])
    }

    @Test func aCapabilityIsAskedForOnceAndThenKnown() async throws {
        let transport = ScriptedTransport(
            transcript: """
                S: * OK ready
                C: A1 LOGIN "dana@example.com" "secret"
                S: A1 OK logged in
                C: A2 CAPABILITY
                S: * CAPABILITY IMAP4rev1 IDLE
                S: A2 OK
                """)
        let connection = try await IMAPConnection(transport: transport, security: .tls)
        try await connection.login(user: "dana@example.com", password: "secret")
        #expect(try await connection.supports("IDLE"))
        #expect(try await connection.supports("QRESYNC") == false)
    }
}
