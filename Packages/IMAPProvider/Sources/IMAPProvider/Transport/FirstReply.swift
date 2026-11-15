import Synchronization

/// Awaits a completion-handler API that may call its handler more than once, keeping the first answer.
///
/// `URLSessionStreamTask` calls a read's handler twice in some cases (a quiet connection's timeout followed by a
/// late callback), and the SDK's own async `readData` resumes a checked continuation from that handler, so the
/// second call traps the app (TestFlight build 9). Bridging the handler here lets only the first call through.
func firstReply<Value: Sendable>(
    _ start: (_ reply: @escaping @Sendable (Result<Value, any Error>) -> Void) -> Void
) async throws -> Value {
    try await withCheckedThrowingContinuation { continuation in
        let pending = PendingReply(continuation)
        start { pending.resume(with: $0) }
    }
}

/// The continuation `firstReply` waits on, taken by whichever reply comes first.
private final class PendingReply<Value: Sendable>: Sendable {
    private let continuation: Mutex<CheckedContinuation<Value, any Error>?>

    init(_ continuation: CheckedContinuation<Value, any Error>) {
        self.continuation = Mutex(continuation)
    }

    func resume(with result: Result<Value, any Error>) {
        continuation.withLock { $0.take() }?.resume(with: result)
    }
}
