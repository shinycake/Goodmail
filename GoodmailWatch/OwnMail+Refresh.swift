import Foundation
import MailWrist
import MailWristHost
import OSLog
import WatchKit
import WidgetKit

/// The watch checks the mail it reads itself in the background too (ADR-023), as often as `WristRefreshPlan` allows.
extension OwnMail {
    /// Names the app's background refresh to the system.
    nonisolated static let refreshIdentifier = "own-mail"

    /// One background refresh: fetches what changed, shows it, stores the mailbox and reloads the watch face before
    /// the system suspends the app, then asks for the next. When the system cuts the time short, the catch-up stops
    /// and what came in so far is kept.
    func refresh(inbox: WristInboxModel, threads: WristThreads, store: WristStore) async {
        defer { Self.scheduleRefresh(after: .now) }
        guard let host = await opening.value else { return }
        await host.catchUp()
        do {
            if let snapshot = try await Self.latest(of: host) {
                Self.show(snapshot, sources: try? await host.sources(), in: inbox, threads)
            }
            try await store.save(inbox.mailbox)
        } catch {
            Self.log.error("Couldn't keep the watch's refreshed mail: \(error, privacy: .public)")
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Asks the system for the next background refresh, unless Low Power Mode is on, where the watch checks only while
    /// the app is open.
    static func scheduleRefresh(after lastRun: Date) {
        guard
            let date = WristRefreshPlan.next(
                after: lastRun, lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
        else { return }
        WKApplication.shared().scheduleBackgroundRefresh(
            withPreferredDate: date, userInfo: refreshIdentifier as NSString
        ) { error in
            if let error { log.error("Couldn't schedule the watch's refresh: \(error, privacy: .public)") }
        }
    }

    /// The watch's own Inbox as it is now.
    @concurrent private static func latest(of host: WristOwnHost) async throws -> WristSnapshot? {
        for try await snapshot in host.snapshots() { return snapshot }
        return nil
    }
}
