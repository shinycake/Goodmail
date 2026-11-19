/// The completion handler the system hands an alert delegate on its own queue, carried to the main actor and called
/// there once the answer is done. Shared by the iPhone and Apple Watch apps' alert delegates, which take the handler
/// rather than being `async`: the `async` forms call the system's handler wherever their body finishes, off the main
/// thread for a `nonisolated` delegate, where UIKit asserts and the app aborts.
///
/// `@unchecked Sendable` because the handler's type isn't `Sendable`. Safe: it is created on the system's queue,
/// never touched there again, and called only on the main actor, once.
public struct MainActorCompletion: @unchecked Sendable {
    private let handler: () -> Void

    public init(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    /// Calls the system's handler. Call it once, on the main actor.
    @MainActor public func call() {
        handler()
    }
}
