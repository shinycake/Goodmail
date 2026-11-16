/// When a process must suspend its databases. iOS kills an app or extension it suspends while it holds a SQLite lock
/// in the App Group container (0xdead10cc), so a suspended database releases its locks and takes no new ones.
///
/// In the foreground nothing is suspended. In the background the database stays usable only while some work that
/// keeps the process awake (a background task, a background refresh) is running; with none left, iOS may suspend the
/// process at any moment.
public struct DatabaseSuspension: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        case foreground
        case background
    }

    /// One piece of running work, from `begin()` to `end(_:)`.
    public struct Work: Hashable, Sendable {
        fileprivate let id: Int
    }

    public private(set) var phase: Phase
    private var running: Set<Work> = []
    private var nextID = 0

    public init(phase: Phase) {
        self.phase = phase
    }

    public var isSuspended: Bool { phase == .background && running.isEmpty }

    public mutating func enter(_ phase: Phase) {
        self.phase = phase
    }

    public mutating func begin() -> Work {
        defer { nextID += 1 }
        let work = Work(id: nextID)
        running.insert(work)
        return work
    }

    /// Ending work twice, as when its time ran out before it finished, changes nothing the second time.
    public mutating func end(_ work: Work) {
        running.remove(work)
    }
}
