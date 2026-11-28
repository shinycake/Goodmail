#if canImport(os)
    import os
#endif

/// One kind of interval the app marks for Instruments and the performance tests (`XCTOSSignpostMetric`), under the
/// subsystem `com.idanbirman.goodmail` and the category `Performance`. On Linux it marks nothing.
///
/// Each feature names its own interval next to the code it measures, as `extension Signpost { static let … }`, so
/// this file never grows with them. An interval that starts in one place and ends in another, once, is a `Once` its
/// owner keeps.
public struct Signpost: Sendable {
    /// The name Instruments shows and the performance tests look for.
    public let name: StaticString

    public init(_ name: StaticString) {
        self.name = name
    }

    /// One interval under way, which `end(_:)` closes.
    public struct Interval: Sendable {
        #if canImport(os)
            fileprivate let state: OSSignpostIntervalState
        #endif
    }

    #if canImport(os)
        // The performance UI tests name this subsystem and category, and the intervals' names, to find them.
        private static let signposter = OSSignposter(subsystem: "com.idanbirman.goodmail", category: "Performance")
    #endif

    /// Starts an interval. `detail` tells it apart from others of its kind, such as the account a sync is for; it is
    /// private, so the system log shows only a hash of it outside a debugging session.
    public func begin(_ detail: String? = nil) -> Interval {
        #if canImport(os)
            let signposter = Self.signposter
            let id = signposter.makeSignpostID()
            guard let detail else { return Interval(state: signposter.beginInterval(name, id: id)) }
            return Interval(state: signposter.beginInterval(name, id: id, "\(detail, privacy: .private(mask: .hash))"))
        #else
            return Interval()
        #endif
    }

    public func end(_ interval: Interval) {
        #if canImport(os)
            Self.signposter.endInterval(name, interval.state)
        #endif
    }

    /// Runs `work` inside an interval, which ends however `work` does. `work` runs where the caller does
    /// (`nonisolated(nonsending)`), so an actor's or the main actor's state can be used in it.
    public nonisolated(nonsending) func measure<T>(_ detail: String? = nil, _ work: () async throws -> T) async rethrows
        -> T
    {
        let interval = begin(detail)
        defer { end(interval) }
        return try await work()
    }
}

extension Signpost {
    /// An interval that one place starts and another ends, at most once each: a second `begin()` does nothing, and so
    /// does an `end()` before `begin()` or after the first `end()`.
    public struct Once: Sendable {
        private enum State: Sendable {
            case idle
            case running(Interval)
            case ended
        }

        private let signpost: Signpost
        private var state = State.idle

        public init(_ signpost: Signpost) {
            self.signpost = signpost
        }

        public mutating func begin() {
            guard case .idle = state else { return }
            state = .running(signpost.begin())
        }

        /// Ends the interval if it is running. Returns whether this call ended it.
        @discardableResult
        public mutating func end() -> Bool {
            guard case .running(let interval) = state else { return false }
            signpost.end(interval)
            state = .ended
            return true
        }
    }
}
