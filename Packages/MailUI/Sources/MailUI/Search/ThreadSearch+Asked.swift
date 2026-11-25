import MailCore
import Synchronization

extension ThreadSearch {
    /// Where asking the provider about the current text stands. Each new text replaces it whole, and a call it held is
    /// cancelled as it goes, checking for that before it changes anything, so a late answer for an old text or an old
    /// page never lands.
    nonisolated enum Asked: Sendable {
        /// Nothing to go on from: the text is blank, or the provider didn't answer, which a refresh asks again.
        case nothing
        /// The first page is on its way, after the pause typing gets, or at once for a refresh.
        case asking(Call)
        /// The provider's matches so far, and the last page of them, which says where the next starts.
        case paged([ThreadSummary.ID], last: SearchPage)
        /// The next page is on its way, which another ask joins.
        case fetchingMore([ThreadSummary.ID], last: SearchPage, Call)
        /// The first page is asked for again, as pull to refresh does, while the matches so far stay.
        case refreshing([ThreadSummary.ID], last: SearchPage, Call)

        /// The provider's matches the results show.
        var found: [ThreadSummary.ID] {
            switch self {
            case .nothing, .asking: []
            case .paged(let found, _), .fetchingMore(let found, _, _), .refreshing(let found, _, _): found
            }
        }

        var call: Call? {
            switch self {
            case .nothing, .paged: nil
            case .asking(let call), .fetchingMore(_, _, let call), .refreshing(_, _, let call): call
            }
        }

        /// Adds `waiter` to the call on its way, or says there is none.
        mutating func wait(_ waiter: Waiter) -> Bool {
            switch self {
            case .nothing, .paged:
                return false
            case .asking(var call):
                call.waiting.append(waiter)
                self = .asking(call)
            case .fetchingMore(let found, let last, var call):
                call.waiting.append(waiter)
                self = .fetchingMore(found, last: last, call)
            case .refreshing(let found, let last, var call):
                call.waiting.append(waiter)
                self = .refreshing(found, last: last, call)
            }
            return true
        }
    }

    /// A call to the provider on its way, and who waits for how it ends. Waiting on it rather than on its task lets a
    /// caller go on as soon as it is replaced, without waiting for an answer that will be dropped.
    nonisolated struct Call: Sendable {
        let task: Task<Void, Never>
        var waiting: [Waiter] = []

        init(_ task: Task<Void, Never>) {
            self.task = task
        }

        /// Stops the call, if it is still on its way, and tells everyone waiting `outcome`.
        func end(_ outcome: Result<Void, any Error>) {
            task.cancel()
            for waiter in waiting { waiter.resume(outcome) }
        }
    }

    /// Someone waiting for a call, who hears how it ended once: when it ends or is replaced, or as soon as the waiting
    /// task is cancelled, whichever comes first. Cancellation arrives on any thread, hence the lock.
    nonisolated final class Waiter: Sendable {
        private enum State {
            /// Not waiting yet.
            case ready
            case waiting(CheckedContinuation<Void, any Error>)
            /// It has heard, or heard before it began to wait, which it then hears at once.
            case ended(Result<Void, any Error>)
        }

        private let state = Mutex(State.ready)

        /// Waits for `resume`, which may have come already.
        func wait() async throws {
            try await withCheckedThrowingContinuation { continuation in
                let ended: Result<Void, any Error>? = state.withLock { state in
                    guard case .ended(let outcome) = state else {
                        state = .waiting(continuation)
                        return nil
                    }
                    return outcome
                }
                if let ended { continuation.resume(with: ended) }
            }
        }

        /// Tells it `outcome`, unless it heard already.
        func resume(_ outcome: Result<Void, any Error>) {
            let waiting: CheckedContinuation<Void, any Error>? = state.withLock { state in
                switch state {
                case .ended:
                    return nil
                case .ready:
                    state = .ended(outcome)
                    return nil
                case .waiting(let continuation):
                    state = .ended(outcome)
                    return continuation
                }
            }
            waiting?.resume(with: outcome)
        }
    }
}
