import Foundation
import GRDB
import MailCore

extension MailDatabase {
    /// Stored snippets as providers make them now (`SnippetText.words(of:)`), without preheader filler. Reads the
    /// threads a page at a time, as the Notification Service Extension can be the process that migrates, with little
    /// memory to spare. The sync state stays, so push alerts carry on before the app next runs.
    static func repairSnippets(_ db: Database) throws {
        var after: (accountID: String, id: String) = ("", "")
        while true {
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT thread.accountID, thread.id, thread.snippet, account.service IN ('icloud', 'imap') AS isIMAP
                    FROM thread JOIN account ON account.id = thread.accountID
                    WHERE (thread.accountID, thread.id) > (?, ?)
                    ORDER BY thread.accountID, thread.id LIMIT 500
                    """,
                arguments: [after.accountID, after.id])
            guard let last = rows.last else { return }
            after = (last["accountID"], last["id"])
            for row in rows {
                let snippet: String = row["snippet"]
                let isIMAP: Bool = row["isIMAP"]
                let repaired = SnippetText.words(of: isIMAP ? readAgain(snippet) : snippet)
                guard repaired != snippet else { continue }
                try db.execute(
                    sql: "UPDATE thread SET snippet = ? WHERE accountID = ? AND id = ?",
                    arguments: [repaired, row["accountID"], row["id"]])
            }
        }
    }

    /// An IMAP snippet whose UTF-8 was read as Latin-1, because the fetched bytes ended partway through a character,
    /// read as UTF-8 again. Such a snippet holds C1 controls (U+0080–U+009F), the continuation bytes of its characters.
    /// Its whitespace was already joined into plain spaces, which took the second byte of each no-break space, so a
    /// lone 0xC2 before a space is left out, as is a character the 200-character cut split. Anything else that isn't
    /// UTF-8, as Windows-1252 text whose smart quotes are C1 controls in Latin-1, stays as it is.
    static func readAgain(_ snippet: String) -> String {
        guard snippet.unicodeScalars.contains(where: { (0x80...0x9F).contains($0.value) }),
            let latin1 = snippet.data(using: .isoLatin1)
        else { return snippet }
        var bytes = [UInt8]()
        for (index, byte) in latin1.enumerated() {
            let next = index + 1 < latin1.count ? latin1[latin1.startIndex + index + 1] : nil
            if byte == 0xC2, next == nil || next == 0x20 { continue }
            bytes.append(byte)
        }
        let readings = (0...3).lazy.compactMap { String(data: Data(bytes.dropLast($0)), encoding: .utf8) }
        return readings.first ?? snippet
    }
}
