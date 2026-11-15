import Foundation
import Testing

@testable import IMAPProvider

/// Keeping the Inbox in IDLE on a connection of its own while the app is open.
struct WatcherTests {
    static func login(capabilities: String = "IMAP4rev1 IDLE") -> String {
        """
        S: * OK ready
        C: A1 LOGIN "dana@icloud.com" "abcd-efgh-ijkl-mnop"
        S: A1 OK authenticated
        C: A2 CAPABILITY
        S: * CAPABILITY \(capabilities)
        S: A2 OK CAPABILITY completed
        """
    }

    /// Logged in, the Inbox open and the first IDLE sent, as each connection of the watcher starts.
    static let idling = login() + "\n" + IMAPClientTests.select("INBOX", tag: 3) + "\nC: A4 IDLE\nS: + idling"

    static func watcher(_ transcripts: String...) -> (IMAPWatcher, [ScriptedTransport]) {
        let scripted = transcripts.map { ScriptedTransport(transcript: $0) }
        let transports = Transports(scripted)
        let connector = IMAPConnector(credentials: IMAPClientTests.credentials, security: .tls) {
            try await transports.next()
        }
        return (IMAPWatcher(connector: connector, renewal: .seconds(3600), retryDelay: { _ in .zero }), scripted)
    }

    /// Runs the watcher until it has reported `count` changes, then cancels it.
    static func changes(_ count: Int, from watcher: IMAPWatcher) async throws {
        let (changes, changed) = AsyncStream.makeStream(of: Void.self)
        let watching = Task { try await watcher.watch { changed.yield() } }
        var seen = 0
        for await _ in changes {
            seen += 1
            if seen == count { break }
        }
        watching.cancel()
        await #expect(throws: CancellationError.self) { try await watching.value }
    }

    @Test func reportsWhatItMissedOnConnectingThenEachChange() async throws {
        let (watcher, transports) = Self.watcher(
            Self.idling + "\nS: * 5 EXISTS\nC: DONE\nS: A4 OK IDLE terminated\nC: A5 IDLE\nS: + idling\n-- silent")
        try await Self.changes(2, from: watcher)
        #expect(await transports[0].isClosed)
    }

    @Test func connectsAgainWhenTheServerDropsTheConnection() async throws {
        let (watcher, transports) = Self.watcher(Self.idling + "\n-- dropped", Self.idling + "\n-- silent")
        try await Self.changes(2, from: watcher)
        for transport in transports { #expect(await transport.isClosed) }
    }

    @Test func connectsAgainWhenTheServerCantBeReached() async throws {
        // Opening the first connection fails before the server says anything.
        let (watcher, _) = Self.watcher("-- dropped", Self.idling + "\n-- silent")
        try await Self.changes(1, from: watcher)
    }

    @Test func aServerWithoutIdleLeavesTheAccountToPolling() async throws {
        let (watcher, transports) = Self.watcher(
            Self.login(capabilities: "IMAP4rev1") + "\nC: A3 LOGOUT\nS: * BYE\nS: A3 OK")
        try await watcher.watch { Issue.record("nothing to report without IDLE") }
        #expect(await transports[0].isClosed)
    }

    @Test func aRefusedPasswordStopsTheWatch() async throws {
        let (watcher, _) = Self.watcher(
            "S: * OK ready\nC: A1 LOGIN \"dana@icloud.com\" \"abcd-efgh-ijkl-mnop\"\nS: A1 NO [AUTHENTICATIONFAILED] no"
        )
        await #expect(throws: IMAPError.authenticationFailed) { try await watcher.watch {} }
    }

    @Test(arguments: [(1, 5), (2, 10), (3, 20), (7, 300), (40, 300)])
    func retriesBackOffToFiveMinutes(failures: Int, seconds: Int64) {
        #expect(IMAPWatcher.backoff(failures) == .seconds(seconds))
    }
}
