import Foundation
import MailCore
import MailStore
import OSLog
import UIKit

/// Giving the reader's storage back after mail leaves the database (ADR-044): SQLite keeps the space deleted mail took
/// inside its file until it's handed back, so without this, removing downloaded mail changed nothing iOS Settings
/// shows.
extension AppModel {
    /// Whether giving storage back may rewrite a database file made before ADR-044 now. The rewrite copies all the
    /// mail, so it runs only while the reader is in the app, or on a Mac, which never suspends the app under it.
    var mayRewriteDatabase: Bool {
        ProcessInfo.processInfo.isMacCatalystApp || UIApplication.shared.applicationState == .active
    }

    /// Gives back what the database no longer needs on disk, off the main thread, keeping the app awake for it if it
    /// leaves the foreground meanwhile. It changes no mail, so a failure costs only the space, and is logged.
    nonisolated static func reclaimDisk(
        _ database: OffMainDatabase, _ reason: DiskReclaim.Reason, mayRewrite: Bool
    ) async {
        await BackgroundDatabaseWork.shared.run("Give storage back") {
            do {
                let free = try volumeFree()
                let outcome = try await database.offMain {
                    try $0.reclaimDisk(reason, volumeFree: free, mayConvert: mayRewrite)
                }
                Logger.storage.info("Gave storage back: \(String(describing: outcome), privacy: .public)")
            } catch {
                Logger.storage.error("Couldn't give storage back: \(error, privacy: .private)")
            }
        }
    }

    /// The space left for files the reader needs on the database's volume, which decides whether a rewrite fits.
    private nonisolated static func volumeFree() throws -> Int64 {
        let folder = SharedContainer.directoryURL ?? URL.applicationSupportDirectory
        let values = try folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values.volumeAvailableCapacityForImportantUsage ?? 0
    }
}

extension Logger {
    nonisolated static let storage = Logger(subsystem: "com.idanbirman.goodmail", category: "storage")
}
