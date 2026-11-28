/// How much of a mailbox a list reads from the store: its newest threads, or every one (ADR-046). A long mailbox opens
/// on its newest screenfuls and reads further as the reader nears the end of them, so the first rows never wait for
/// 50,000 to be read and decoded.
public enum ThreadWindow: Hashable, Sendable {
    /// The newest `count` threads, newest first.
    case newest(Int)
    /// Every thread, newest first.
    case whole

    /// How many threads a list reads first: a few screenfuls, more than a tall window shows at once.
    public static let firstCount = 200

    /// How many threads it reads at most, or `nil` for every one.
    public var limit: Int? {
        switch self {
        case .newest(let count): count
        case .whole: nil
        }
    }
}

/// What the store lists of a mailbox for a `ThreadWindow`.
public struct ThreadListing: Equatable, Sendable {
    /// The threads in the window, newest first.
    public var threads: [ThreadSummary]
    /// Pinned threads, and threads back from snooze, that are in the mailbox but below the window, newest first. A
    /// list leads with these whatever their date, so it shows them before the reader reaches them.
    public var held: [ThreadSummary]
    /// Whether the window holds the mailbox's every thread.
    public var reach: Reach

    /// Whether a window reaches the end of its mailbox.
    public enum Reach: Equatable, Sendable {
        /// Every thread in the mailbox is in the window, so older ones can only come from the service.
        case whole
        /// The mailbox holds more threads below the window.
        case more
    }

    public init(threads: [ThreadSummary], held: [ThreadSummary] = [], reach: Reach) {
        self.threads = threads
        self.held = held
        self.reach = reach
    }

    /// Every thread of a list that is never windowed, as search's results.
    public init(whole threads: [ThreadSummary]) {
        self.init(threads: threads, reach: .whole)
    }
}
