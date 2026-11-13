import MailCore
import Network
import Synchronization

/// Tells prefetch whether the connection suits bulk downloads: up, and neither expensive (cellular, a personal
/// hotspot) nor constrained (Low Data Mode). Unknown until the first path report, which comes within moments.
nonisolated final class PathMonitor: NetworkPath, Sendable {
    private struct State {
        var allowed = false
        var listeners: [UInt64: AsyncStream<Void>.Continuation] = [:]
        var nextListener: UInt64 = 0
    }

    private let monitor = NWPathMonitor()
    private let state = Mutex(State())

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.update(allowed: path.status == .satisfied && !path.isExpensive && !path.isConstrained)
        }
        monitor.start(queue: DispatchQueue(label: "com.idanbirman.goodmail.path"))
    }

    deinit {
        monitor.cancel()
    }

    var allowsBulkDownload: Bool { state.withLock { $0.allowed } }

    /// Emits each time the connection turns cheap, as when Wi-Fi comes back, until the iterating task is cancelled.
    func becameAllowed() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        let id = state.withLock { state in
            defer { state.nextListener += 1 }
            state.listeners[state.nextListener] = continuation
            return state.nextListener
        }
        continuation.onTermination = { [weak self] _ in
            _ = self?.state.withLock { $0.listeners.removeValue(forKey: id) }
        }
        return stream
    }

    private func update(allowed: Bool) {
        let woken = state.withLock { state in
            defer { state.allowed = allowed }
            return allowed && !state.allowed ? Array(state.listeners.values) : []
        }
        for listener in woken { listener.yield() }
    }
}
