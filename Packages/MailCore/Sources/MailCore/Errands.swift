/// Runs async work started from synchronous code, such as a callback the system makes or a closure a command calls
/// as it changes mail, as children of one task its owner holds, so none of it outlives the owner. Errands run side by
/// side, each as a child task of its own; nothing promises one starts at once, or before an errand started after it.
///
/// `cancel()`, or the owner letting go of it, cancels every errand under way and drops any not yet under way: one
/// still waiting its turn when the cancel lands, and any started after.
public final class Errands: Sendable {
    public typealias Errand = @Sendable () async -> Void

    private let errands: AsyncStream<Errand>.Continuation
    /// Takes each errand off the stream and runs it as a child, until the stream ends or the runner is cancelled.
    private let runner: Task<Void, Never>

    public init() {
        let (stream, errands) = AsyncStream.makeStream(of: Errand.self)
        self.errands = errands
        runner = Task {
            await withDiscardingTaskGroup { group in
                for await errand in stream {
                    // Once cancelled the group starts nothing more, so an errand still buffered then is dropped.
                    guard group.addTaskUnlessCancelled(operation: { await errand() }) else { break }
                }
            }
        }
    }

    deinit {
        cancel()
    }

    /// Hands `errand` to the runner, which starts it beside any under way, unless `cancel()` lands first.
    public func start(_ errand: @escaping Errand) {
        errands.yield(errand)
    }

    /// Cancels every errand under way, and drops any not yet under way or started from now on.
    public func cancel() {
        // Cancelled first, so an errand the runner takes off the stream once it is finished finds the group cancelled.
        runner.cancel()
        errands.finish()
    }

    /// Waits until the runner has stopped: after `cancel()`, once every errand under way has ended.
    public func ended() async {
        await runner.value
    }
}
