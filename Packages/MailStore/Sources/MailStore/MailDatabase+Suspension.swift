import Foundation
import GRDB

extension MailDatabase {
    /// Suspends every database in this process: GRDB interrupts what holds a lock and takes no new ones, so writes
    /// throw (`SQLITE_INTERRUPT` or `SQLITE_ABORT`) and reads still work. Call it before iOS may suspend the process
    /// (see `DatabaseSuspension`).
    public static func suspendAll() {
        NotificationCenter.default.post(name: Database.suspendNotification, object: nil)
    }

    /// Ends `suspendAll()`.
    public static func resumeAll() {
        NotificationCenter.default.post(name: Database.resumeNotification, object: nil)
    }
}
