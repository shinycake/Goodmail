import Foundation
import GRDB
import MailCore

extension MailDatabase {
    /// People who wrote to any account whose name or address starts with `text` (or has a word that does), most
    /// frequent first, then most recent. The accounts' own addresses are left out.
    public func contacts(matching text: String, limit: Int = 5) throws -> [Contact] {
        let typed = text.trimmingCharacters(in: .whitespaces)
        guard !typed.isEmpty else { return [] }
        let escaped = typed.replacing("\\", with: "\\\\").replacing("%", with: "\\%").replacing("_", with: "\\_")
        return try pool.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT max(senderAddress) AS senderAddress, max(senderName) AS name
                    FROM thread
                    WHERE (senderAddress LIKE :prefix ESCAPE '\\' OR senderName LIKE :prefix ESCAPE '\\'
                        OR senderName LIKE :word ESCAPE '\\')
                    AND lower(senderAddress) NOT IN (SELECT lower(email) FROM account)
                    GROUP BY lower(senderAddress)
                    ORDER BY count(*) DESC, max(date) DESC
                    LIMIT :limit
                    """,
                arguments: ["prefix": escaped + "%", "word": "% " + escaped + "%", "limit": limit]
            )
            .map { Contact(name: $0["name"], address: $0["senderAddress"]) }
        }
    }
}
