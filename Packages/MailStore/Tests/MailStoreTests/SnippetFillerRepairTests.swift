import Foundation
import GRDB
import MailCore
import Testing

@testable import MailStore

/// Snippets stored with a marketing mail's preheader filler, or with that filler read as Latin-1 over IMAP, are
/// repaired the first time the database opens, without a resync that would hold back push alerts until the app runs.
struct SnippetFillerRepairTests {
    private let url = FileManager.default.temporaryDirectory
        .appending(path: "SnippetFillerRepairTests-\(UUID().uuidString)")
        .appending(path: "mail.sqlite")
    private static let filler = "Our only sale of the year! \u{034F} \u{200C}\u{00A0}\u{034F} \u{200C}\u{00A0}"
    /// `filler`'s UTF-8 read as Latin-1, C1 controls and all, with its no-break space joined into a plain one.
    private static let misread =
        "Our only sale of the year! \u{00CD}\u{008F} \u{00E2}\u{0080}\u{008C}\u{00C2} \u{00C3}\u{00A9}t\u{00C3}\u{00A9}"

    @Test func storedSnippetsLoseTheirFillerAndMisreadIMAPOnesReadAgain() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let pool = try DatabasePool(path: url.path)
        try MailDatabase.migrator.migrate(pool, upTo: "v32-watch-token")
        let accounts: [(id: String, service: MailService, snippet: String)] = [
            ("gmail", .gmail, Self.filler),
            ("icloud", .icloud, Self.misread),
            ("outlook", .outlook, Self.misread),
            ("imap", .imap, "Lunch at noon?"),
            // Windows-1252 read as Latin-1 has C1 controls too, but isn't UTF-8.
            ("windows1252", .imap, "Caf\u{E9} na\u{EF}ve, don\u{92}t miss it"),
        ]
        let cursor = String(decoding: try JSONEncoder().encode(SyncState.current(cursor: "c1")), as: UTF8.self)
        try pool.write { db in
            for account in accounts {
                try db.execute(
                    sql: "INSERT INTO account (id, email, color, createdAt, service) VALUES (?, ?, 'teal', ?, ?)",
                    arguments: [account.id, "\(account.id)@example.com", Date.now, account.service.rawValue])
                try db.execute(
                    sql: "INSERT INTO syncState (accountID, state) VALUES (?, ?)", arguments: [account.id, cursor])
                let thread = ThreadSummary(
                    id: .init(accountID: AccountID(rawValue: account.id), threadID: "t"), subject: "Sale",
                    snippet: account.snippet, sender: Contact(name: nil, address: "crew@example.com"), date: .now,
                    isUnread: true, messageCount: 1, labelIDs: [])
                try MailDatabase.upsert(thread, in: db)
            }
        }
        try pool.close()

        let database = try MailDatabase(url: url)

        let stored = try database.threads(accounts.map { .init(accountID: AccountID(rawValue: $0.id), threadID: "t") })
        let snippets = Dictionary(uniqueKeysWithValues: stored.map { ($0.id.accountID.rawValue, $0.snippet) })
        // Only IMAP reads a snippet's bytes, so only an IMAP snippet can have been misread.
        #expect(
            snippets == [
                "gmail": "Our only sale of the year!", "icloud": "Our only sale of the year! été",
                "outlook": Self.misread, "imap": "Lunch at noon?",
                "windows1252": "Caf\u{E9} na\u{EF}ve, don\u{92}t miss it",
            ])
        for account in accounts {
            #expect(try database.syncState(for: AccountID(rawValue: account.id)) == .current(cursor: "c1"))
        }
    }
}
