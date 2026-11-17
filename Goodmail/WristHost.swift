import Foundation
import MailCore
import MailStore
import MailWrist
import OSLog

/// The iPhone's side of the Apple Watch app (ADR-022): it keeps the watch's copy of the Inbox current. Each change to
/// the Inbox, from a sync or from the reader, becomes a snapshot that the watch gets the next time it can.
final class WristHost {
    private let database: MailDatabase
    private let channel = WristChannel()
    /// Follows the Inbox and the session for the app's lifetime.
    private var following: Task<Void, Never>?

    init(database: MailDatabase) {
        self.database = database
    }

    func start() {
        following = Task { @concurrent [database, channel] in
            await channel.activate()
            await withDiscardingTaskGroup { group in
                group.addTask {
                    // A watch that was just paired, or whose app was just installed, gets what couldn't be sent.
                    for await event in channel.events where event == .ready { await channel.sendUnsent() }
                }
                group.addTask {
                    do {
                        for try await glance in database.inboxGlance(limit: WristSnapshot.rowLimit) {
                            await channel.send(
                                WristSnapshot(
                                    accounts: glance.accounts, threads: glance.threads, pinned: glance.pinned,
                                    unread: glance.unread, madeAt: .now))
                        }
                    } catch {
                        Logger(subsystem: "com.idanbirman.goodmail", category: "wrist")
                            .error("Stopped sending the Inbox to the watch: \(error, privacy: .public)")
                    }
                }
            }
        }
    }
}
