import Synchronization

/// Awaits a completion-handler API that may call its handler more than once, keeping the first answer, and stops
/// waiting with `CancellationError` as soon as the caller is cancelled.
///
/// `URLSessionStreamTask` calls a read's handler twice in some cases (a quiet connection's timeout followed by a
/// late callback), and the SDK's own async `readData` resumes a checked continuation from that handler, so the
/// second call traps the app (TestFlight build 9). Bridging the handler here lets only the first call through.
///
/// A read never hears of cancellation by itself, so without the cancellation answer an IDLE watch cancelled as the
/// app leaves the foreground kept its connection open until its read timed out, ten minutes later. The handler's
/// late call after a cancellation is dropped like any other second answer.
func firstReply<Value: Sendable>(
    _ start: (_ reply: @escaping @Sendable (Result<Value, any Error>) -> Void) -> Void
) async throws -> Value {
    let pending = PendingReply<Value>()
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            guard pending.wait(continuation) else { return }
            start { pending.answer($0) }
        }
    } onCancel: {
        pending.answer(.failure(CancellationError()))
    }
}

/// The continuation `firstReply` waits on, taken by whichever answer comes first: a reply or the cancellation.
private final class PendingReply<Value: Sendable>: Sendable {
    private enum State {
        /// `firstReply` hasn't handed over its continuation yet.
        case starting
        case waiting(CheckedContinuation<Value, any Error>)
        /// Answered. When the cancellation came before the continuation, `wait` answers it at once.
        case answered(Result<Value, any Error>)
        case done
    }

    private let state = Mutex(State.starting)

    /// Takes the continuation, or answers it at once when the caller was cancelled first. Returns whether to start
    /// the operation.
    func wait(_ continuation: CheckedContinuation<Value, any Error>) -> Bool {
        let early: Result<Value, any Error>? = state.withLock { state in
            switch state {
            case .starting:
                state = .waiting(continuation)
                return nil
            case .answered(let result):
                state = .done
                return result
            case .waiting, .done:
                preconditionFailure("firstReply waits once")
            }
        }
        guard let early else { return true }
        continuation.resume(with: early)
        return false
    }

    /// The first answer resumes the waiting caller; any later one is dropped.
    func answer(_ result: Result<Value, any Error>) {
        let continuation: CheckedContinuation<Value, any Error>? = state.withLock { state in
            switch state {
            case .starting:
                state = .answered(result)
                return nil
            case .waiting(let continuation):
                state = .done
                return continuation
            case .answered, .done:
                return nil
            }
        }
        continuation?.resume(with: result)
    }
}
