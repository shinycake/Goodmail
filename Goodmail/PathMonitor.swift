import MailCore
import Network
import Synchronization

/// Tells prefetch whether the connection suits bulk downloads: up, and neither expensive (cellular, a personal
/// hotspot) nor constrained (Low Data Mode). Unknown until the first path report, which comes within moments.
nonisolated final class PathMonitor: NetworkPath, Sendable {
    private let monitor = NWPathMonitor()
    private let allowed = Mutex(false)

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let cheap = path.status == .satisfied && !path.isExpensive && !path.isConstrained
            self?.allowed.withLock { $0 = cheap }
        }
        monitor.start(queue: DispatchQueue(label: "com.idanbirman.goodmail.path"))
    }

    deinit {
        monitor.cancel()
    }

    var allowsBulkDownload: Bool { allowed.withLock { $0 } }
}
