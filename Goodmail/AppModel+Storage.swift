import MailCore
import MailStore
import MailUI

extension AppModel {
    /// The Storage page: what the downloaded mail takes, measured and trimmed off the main actor.
    func storageSettings() -> StorageSettings {
        let (database, attachments) = (database, attachmentsDirectory)
        return StorageSettings(
            service: StorageSettings.Service(
                usage: {
                    try await Self.offMain {
                        let usage = try database.cacheUsage(attachments: attachments)
                        return StorageSettings.Usage(messages: usage.bodies, attachments: usage.attachments)
                    }
                },
                trim: { limit in
                    try await Self.offMain { _ = try database.trimCache(to: limit, attachments: attachments) }
                }))
    }
}
