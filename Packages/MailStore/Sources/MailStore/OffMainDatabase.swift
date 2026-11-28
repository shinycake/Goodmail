public import Foundation
import MailCore

/// The mail database as code on the main actor holds it (ADR-043): every read and write is an `await` that runs off
/// the caller's actor, so none can block the main thread, which another process's lock could hold for seconds
/// (ADR-002). The streams (`MailFollowing`) need no hop: they read on GRDB's queues.
///
/// The MailCore actors and the extensions' own off-main code read and write `MailDatabase` directly, which blocks as
/// they need. `blocking` is that database, to hand to them, as into an actor's `init`. Outside MailStore, anything
/// but handing it on whole fails `scripts/check` (`scripts/blocking-reads`), and as the backstop Debug builds trap a
/// read or write made on the main queue.
public struct OffMainDatabase: Sendable {
    /// The blocking database, to hand into an actor or other code that runs off the main thread. Never read or write
    /// through it here.
    public let blocking: MailDatabase

    init(_ database: MailDatabase) {
        blocking = database
    }

    /// Opens (creating if needed) the database at `url` and migrates it, off the caller's actor: after an update,
    /// migrating and filling in what older builds left out can take a while.
    @concurrent public static func open(url: URL) async throws -> OffMainDatabase {
        try await Signpost.databaseOpen.measure { OffMainDatabase(try MailDatabase(url: url)) }
    }

    /// Runs `work` against the database off the caller's actor, and hands back what it returns or throws. A few
    /// reads and writes in one `work` run one after another, with no other hop between them.
    @concurrent public func offMain<T: Sendable, E: Error>(_ work: @Sendable (MailDatabase) throws(E) -> T)
        async throws(E) -> T
    {
        try work(blocking)
    }
}

extension Signpost {
    /// Opening the mail database, with its migrations.
    static let databaseOpen = Signpost("DatabaseOpen")
}
