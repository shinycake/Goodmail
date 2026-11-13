/// Lets at most `limit` pieces of work run at once; the rest wait their turn, first come first served.
actor RequestGate {
    private let limit: Int
    /// Work under way. It's below `limit` only while nothing waits: a freed slot passes straight to the next waiter.
    private var running = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        precondition(limit > 0, "A gate needs at least one slot")
        self.limit = limit
    }

    /// Runs `work` once a slot is free, and frees the slot when it ends, whether it returns or throws. A caller
    /// cancelled while it waits still takes its turn; its work then sees the cancellation and ends at once.
    nonisolated func run<T>(_ work: () async throws -> T) async throws -> T {
        await enter()
        do {
            let result = try await work()
            await leave()
            return result
        } catch {
            await leave()
            throw error
        }
    }

    private func enter() async {
        guard running == limit else {
            running += 1
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    private func leave() {
        if waiting.isEmpty {
            running -= 1
        } else {
            waiting.removeFirst().resume()
        }
    }
}
