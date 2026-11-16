import Foundation
import GRDB
import MailCore
import Testing

@testable import MailStore

/// IMAP snippets stored before they could see past a long style sheet showed the CSS. Opening the database once
/// makes those accounts fill their window again, which stores every thread's snippet anew.
struct SnippetRefillTests {
    private let url = FileManager.default.temporaryDirectory
        .appending(path: "SnippetRefillTests-\(UUID().uuidString)")
        .appending(path: "mail.sqlite")

    @Test func imapAccountsResyncAndTheRestKeepTheirCursor() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let pool = try DatabasePool(path: url.path)
        try MailDatabase.migrator.migrate(pool, upTo: "v28-focus")
        let services: [(id: String, service: MailService)] = [
            ("gmail", .gmail), ("icloud", .icloud), ("outlook", .outlook), ("imap", .imap),
        ]
        let cursor = String(decoding: try JSONEncoder().encode(SyncState.current(cursor: "c1")), as: UTF8.self)
        try pool.write { db in
            for (id, service) in services {
                try db.execute(
                    sql: "INSERT INTO account (id, email, color, createdAt, service) VALUES (?, ?, 'teal', ?, ?)",
                    arguments: [id, "\(id)@example.com", Date.now, service.rawValue])
                try db.execute(
                    sql: "INSERT INTO syncState (accountID, state) VALUES (?, ?)", arguments: [id, cursor])
            }
        }
        try pool.close()

        let database = try MailDatabase(url: url)

        for (id, service) in services {
            let expected: SyncState? = [.icloud, .imap].contains(service) ? nil : .current(cursor: "c1")
            #expect(try database.syncState(for: AccountID(rawValue: id)) == expected, "\(service)")
        }
    }
}
