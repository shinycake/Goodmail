import Synchronization

/// A value that says how new it is: of two, the one with the higher revision was written later, as the stored
/// accounts carry the revision every write to them bumps (ADR-043).
public protocol Revised: Sendable {
    var revision: Int { get }
}

/// The latest value a stream gave, readable at once from any actor, and a way to wait for the value that shows a
/// write: a caller that stored something waits until the followed value is as new as its write, as the app does for an
/// account it just added before it makes the account's session.
///
/// It follows its stream for its whole life, and follows it again shortly after it fails, so one failure doesn't
/// leave the value behind for good. Nothing outside sets it, and it never takes a value older than the one it holds.
public final class FollowedValue<Value: Revised>: Sendable {
    private let state: Shared
    private let read: @Sendable () async throws -> Value
    /// Follows the stream until this value is released.
    private let following: Task<Void, Never>

    /// Starts at `initial` and follows the values `follow` streams. After the stream fails or ends, it follows a new
    /// one after `delay`, twice as long after each failure in a row up to `longest`, and logs only the first; a wait
    /// under way then reads the value once with `read` rather than wait for it.
    public init(
        _ initial: Value, following follow: @escaping @Sendable () -> AsyncThrowingStream<Value, any Error>,
        reading read: @escaping @Sendable () async throws -> Value, againAfter delay: Duration = .seconds(1),
        atMost longest: Duration = .seconds(60), log: MailLog
    ) {
        let state = Shared(initial)
        self.state = state
        self.read = read
        following = Task {
            // How many times in a row the stream ended before it gave a value.
            var failures = 0
            while !Task.isCancelled {
                do {
                    for try await value in follow() {
                        failures = 0
                        state.take(value)
                    }
                } catch {
                    if failures == 0 { log.error("Stopped following a stored value; following it again", error) }
                }
                guard !Task.isCancelled else { return }
                state.letWaitersRead()
                try? await Task.sleep(for: min(delay * (1 << min(failures, 16)), longest))
                failures += 1
            }
        }
    }

    deinit {
        following.cancel()
    }

    /// The newest value given.
    public var latest: Value { state.latest }

    /// Waits until the value is at least as new as `revision`, at once when it already is. If the following fails
    /// meanwhile, reads the value once instead. `false` when the caller was cancelled or that read failed, which
    /// leaves the caller to go on without it.
    public func wait(forRevision revision: Int) async -> Bool {
        switch await state.wait(forRevision: revision) {
        case .shown:
            return true
        case .cancelled:
            return false
        case .followingFailed:
            guard let value = try? await read() else { return false }
            state.take(value)
            return state.latest.revision >= revision
        }
    }

    /// How many callers wait, for tests to know a wait has started.
    var waiting: Int { state.waiting }

    /// How a wait ended.
    private enum Outcome {
        case shown
        case cancelled
        /// The stream failed while it waited, so the value may not follow the write for a while.
        case followingFailed
    }

    /// The value and its waiters, behind one lock.
    private final class Shared: Sendable {
        private struct Waiter {
            let revision: Int
            let continuation: CheckedContinuation<Outcome, Never>
        }

        private struct State {
            var latest: Value
            /// Each waits for a value at least as new as its revision.
            var waiters: [Int: Waiter] = [:]
            var nextWaiter = 0
        }

        private let state: Mutex<State>

        init(_ initial: Value) {
            state = Mutex(State(latest: initial))
        }

        var latest: Value { state.withLock { $0.latest } }
        var waiting: Int { state.withLock { $0.waiters.count } }

        /// Takes `value` unless the one held is newer, and lets go every waiter it shows.
        func take(_ value: Value) {
            let shown = state.withLock { state -> [Waiter] in
                guard value.revision >= state.latest.revision else { return [] }
                state.latest = value
                let met = state.waiters.filter { $0.value.revision <= value.revision }
                for id in met.keys { state.waiters[id] = nil }
                return Array(met.values)
            }
            for waiter in shown { waiter.continuation.resume(returning: .shown) }
        }

        /// The stream failed: every waiter goes to read the value itself.
        func letWaitersRead() {
            let waiting = state.withLock { state -> [Waiter] in
                defer { state.waiters = [:] }
                return Array(state.waiters.values)
            }
            for waiter in waiting { waiter.continuation.resume(returning: .followingFailed) }
        }

        func wait(forRevision revision: Int) async -> Outcome {
            let id = state.withLock { state -> Int in
                defer { state.nextWaiter += 1 }
                return state.nextWaiter
            }
            return await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    // Checked under the lock that `take`, a failure and cancelling take, so none is missed.
                    let answer = state.withLock { state -> Outcome? in
                        if state.latest.revision >= revision { return .shown }
                        if Task.isCancelled { return .cancelled }
                        state.waiters[id] = Waiter(revision: revision, continuation: continuation)
                        return nil
                    }
                    if let answer { continuation.resume(returning: answer) }
                }
            } onCancel: {
                let waiter = state.withLock { $0.waiters.removeValue(forKey: id) }
                waiter?.continuation.resume(returning: .cancelled)
            }
        }
    }
}
