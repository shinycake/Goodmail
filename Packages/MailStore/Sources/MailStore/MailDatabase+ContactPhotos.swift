import Foundation
import GRDB

extension MailDatabase {
    /// The profile photo an address book keeps for `address`, in any account; `nil` when none has one.
    public func photoURL(for address: String) throws -> URL? {
        try pool.read { db in
            try URL.fetchOne(
                db, sql: "SELECT photoURL FROM addressBook WHERE address = ? AND photoURL IS NOT NULL LIMIT 1",
                arguments: [address])
        }
    }
}
