import MailCore
import Network
import Synchronization

/// Tells prefetch how much the connection allows: nothing offline or in Low Data Mode, a little when it is expensive
/// (cellular, a personal hotspot), and the rest otherwise. Nothing until the first path report, which comes within
/// moments.
nonisolated final class PathMonitor: NetworkPath, Sendable {
    private struct State {
        var allowance = NetworkAllowance.none
        var listeners: [UInt64: AsyncStream<Void>.Continuation] = [:]
        var nextListener: UInt64 = 0
    }

    private let monitor = NWPathMonitor()
    private let state = Mutex(State())

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.update(Self.allowance(of: path))
        }
        monitor.start(queue: DispatchQueue(label: "com.idanbirman.goodmail.path"))
    }

    deinit {
        monitor.cancel()
    }

    var allowance: NetworkAllowance { state.withLock { $0.allowance } }

    private static func allowance(of path: NWPath) -> NetworkAllowance {
        guard path.status == .satisfied, !path.isConstrained else { return .none }
        return path.isExpensive ? .metered : .unmetered
    }

    /// Emits each time the connection allows more than it did, as when cellular comes up or Wi-Fi comes back, until
    /// the iterating task is cancelled.
    func allowsMore() -> AsyncStream<Void> {
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

    private func update(_ allowance: NetworkAllowance) {
        let woken = state.withLock { state in
            defer { state.allowance = allowance }
            return allowance > state.allowance ? Array(state.listeners.values) : []
        }
        for listener in woken { listener.yield() }
    }
}
