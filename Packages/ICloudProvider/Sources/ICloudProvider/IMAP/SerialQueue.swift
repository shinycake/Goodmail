/// Runs async operations one at a time, in the order they were started. An actor alone doesn't: it interleaves
/// operations at every `await`, and an IMAP exchange must not be interleaved.
struct SerialQueue {
    /// The operation running now; the next one waits for it.
    private var tail: Task<Void, Never>?

    mutating func run<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) -> Task<T, any Error> {
        let previous = tail
        let task = Task {
            await previous?.value
            return try await operation()
        }
        tail = Task { _ = await task.result }
        return task
    }
}
