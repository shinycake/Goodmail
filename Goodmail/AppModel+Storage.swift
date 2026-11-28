import MailCore
import MailStore
import MailUI

extension AppModel {
    /// The Storage page: what the downloaded mail takes, measured and trimmed off the main actor, and the space it took
    /// given back (ADR-044).
    func storageSettings() -> StorageSettings {
        let (database, attachments) = (database, attachmentsDirectory)
        return StorageSettings(
            service: StorageSettings.Service(
                usage: {
                    try await database.offMain { database in
                        let usage = try database.cacheUsage(attachments: attachments)
                        return StorageSettings.Usage(messages: usage.bodies, attachments: usage.attachments)
                    }
                },
                trim: { limit in
                    try await database.offMain { _ = try $0.trimCache(to: limit, attachments: attachments) }
                    // The reader is on the page, so a file made before ADR-044 may be rewritten now.
                    await AppModel.reclaimDisk(database, .readerAsked, mayRewrite: true)
                }),
            preferences: storage)
    }
}
