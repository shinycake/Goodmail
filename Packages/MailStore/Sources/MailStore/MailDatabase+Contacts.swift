import Foundation
import GRDB
import MailCore

extension MailDatabase {
    /// People whose name or address starts with `text` (or has a word that does): those who wrote to any account,
    /// most frequent first, then most recent, then the rest of the address books. A name from an address book wins
    /// over the one on the mail. The accounts' own addresses are left out.
    public func contacts(matching text: String, limit: Int = 5) throws -> [Contact] {
        let typed = text.trimmingCharacters(in: .whitespaces)
        guard !typed.isEmpty else { return [] }
        let escaped = typed.replacing("\\", with: "\\\\").replacing("%", with: "\\%").replacing("_", with: "\\_")
        return try pool.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT max(address) AS address, coalesce(max(bookName), max(mailName)) AS name
                    FROM (
                        SELECT senderAddress AS address, NULL AS bookName, senderName AS mailName, 1 AS uses,
                            date AS last
                        FROM thread
                        WHERE senderAddress LIKE :prefix ESCAPE '\\' OR senderName LIKE :prefix ESCAPE '\\'
                            OR senderName LIKE :word ESCAPE '\\'
                        UNION ALL
                        SELECT address, name, NULL, 0, NULL
                        FROM addressBook
                        WHERE address LIKE :prefix ESCAPE '\\' OR name LIKE :prefix ESCAPE '\\'
                            OR name LIKE :word ESCAPE '\\'
                    )
                    WHERE lower(address) NOT IN (SELECT lower(email) FROM account)
                    GROUP BY lower(address)
                    ORDER BY sum(uses) DESC, max(last) DESC, name
                    LIMIT :limit
                    """,
                arguments: ["prefix": escaped + "%", "word": "% " + escaped + "%", "limit": limit]
            )
            .map { Contact(name: $0["name"], address: $0["address"]) }
        }
    }
}
