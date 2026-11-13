/// Runs async work on the main actor one piece after another, in the order it was asked for. Separate tasks don't
/// promise that: one that suspends sooner can be overtaken. Each piece here starts only once the one before it ends,
/// so a sequence of the reader's changes lands as they made it.
@MainActor
public final class TaskChain {
    /// The work asked for last; the next piece waits for it.
    private var tail: Task<Void, Never>?

    public init() {}

    public func run(_ work: @escaping @MainActor () async -> Void) {
        let previous = tail
        tail = Task {
            await previous?.value
            await work()
        }
    }

    /// Waits until everything asked for so far has run, as a test does before it looks at the result.
    public func settled() async {
        await tail?.value
    }
}
