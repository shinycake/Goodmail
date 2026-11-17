import Foundation

/// An SMTP connection opened and logged in ahead of a send, while its undo window runs, so the send itself is only
/// the message. On iCloud, connecting, TLS and logging in take about two seconds, and the message a quarter of one.
///
/// It waits at most `longestWait`, then closes: a send that was undone never comes for it, and servers drop a quiet
/// connection after a few minutes anyway.
actor SMTPWaitingConnection {
    private enum State {
        case none
        /// Logging in. `take` waits for it rather than opening a second connection.
        case opening(generation: Int, Task<SMTPConversation?, Never>)
        /// Logged in, until `closing` ends it.
        case ready(generation: Int, SMTPConversation, closing: Task<Void, Never>)
    }

    /// Longer than the longest undo window, 30 seconds, and well inside a server's idle timeout.
    static let longestWait: Duration = .seconds(60)

    private var state = State.none
    private var generation = 0

    /// Opens a connection with `logIn`, unless one is open or opening. A login that fails leaves none, and the send
    /// opens its own.
    func open(with logIn: @escaping @Sendable () async throws -> SMTPConversation) {
        guard case .none = state else { return }
        generation += 1
        let generation = generation
        state = .opening(
            generation: generation,
            Task {
                let conversation = try? await logIn()
                self.opened(conversation, generation: generation)
                return conversation
            })
    }

    /// The waiting connection, which is the caller's to use and close from now on, or `nil` when there is none.
    func take() async -> SMTPConversation? {
        switch state {
        case .none:
            return nil
        case .opening(_, let task):
            // Taken before it finished: `opened` finds it gone and leaves it to this caller.
            state = .none
            return await task.value
        case .ready(_, let conversation, let closing):
            state = .none
            closing.cancel()
            return conversation
        }
    }

    private func opened(_ conversation: SMTPConversation?, generation: Int) {
        guard case .opening(let current, _) = state, current == generation else { return }
        guard let conversation else {
            state = .none
            return
        }
        state = .ready(
            generation: generation, conversation,
            closing: Task {
                guard (try? await Task.sleep(for: Self.longestWait)) != nil else { return }
                await self.expire(generation)
            })
    }

    private func expire(_ generation: Int) async {
        guard case .ready(let current, let conversation, _) = state, current == generation else { return }
        state = .none
        await conversation.transport.close()
    }
}
