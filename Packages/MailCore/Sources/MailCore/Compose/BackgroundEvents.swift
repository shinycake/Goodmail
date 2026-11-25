/// When to tell iOS that the events it woke the app for have been taken in. Three things must have happened, in
/// whatever order they come: iOS handed over the handler to call, it said it delivered every event, and each outcome
/// those carried was taken in. A launch can hear that the events were delivered before the app is far enough along
/// to take the handler, so neither waits on the other.
public struct BackgroundEvents<Handler> {
    private enum Stage {
        /// iOS is delivering events, or has none; the handlers it gave meanwhile wait for the delivery to end.
        case delivering([Handler])
        /// Every event was delivered. The handlers, given before or after, are due once the outcomes are taken in.
        case delivered([Handler])
    }

    private var stage = Stage.delivering([])

    public init() {}

    /// iOS handed over `handler` for the events it's delivering, or delivered.
    public mutating func receive(_ handler: Handler) {
        switch stage {
        case .delivering(let handlers): stage = .delivering(handlers + [handler])
        case .delivered(let handlers): stage = .delivered(handlers + [handler])
        }
    }

    /// iOS said it delivered every event.
    public mutating func delivered() {
        if case .delivering(let handlers) = stage { stage = .delivered(handlers) }
    }

    /// The handlers to call now, each once: those of a delivery whose outcomes are all taken in. The next wake starts
    /// afresh.
    public mutating func due(allTakenIn: Bool) -> [Handler] {
        guard allTakenIn, case .delivered(let handlers) = stage, !handlers.isEmpty else { return [] }
        stage = .delivering([])
        return handlers
    }
}
