import Foundation
import MailCore

/// Search as the user types: the store's matches at once, then the provider's merged in once typing pauses.
public final class ThreadSearch {
    /// The store's threads matching the text, together with the given provider matches.
    public typealias Local = (String, [ThreadSummary.ID]) -> AsyncThrowingStream<[ThreadSummary], any Error>

    private let local: Local
    private let remote: (String) async throws -> [ThreadSummary.ID]
    private let pause: Duration
    private var text = ""
    private var continuation: AsyncThrowingStream<[ThreadSummary], any Error>.Continuation?
    private var following: Task<Void, Never>?
    private var asking: Task<Void, Never>?

    public init(
        local: @escaping Local, remote: @escaping (String) async throws -> [ThreadSummary.ID],
        pause: Duration = .milliseconds(400)
    ) {
        self.local = local
        self.remote = remote
        self.pause = pause
    }

    deinit {
        following?.cancel()
        asking?.cancel()
    }

    /// The results for the current text, updated as it changes. One reader at a time: a new call ends the last.
    public func results() -> AsyncThrowingStream<[ThreadSummary], any Error> {
        continuation?.finish()
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: [ThreadSummary].self)
        self.continuation = continuation
        follow(including: [])
        return stream
    }

    public func update(_ text: String) {
        guard text != self.text else { return }
        self.text = text
        follow(including: [])
        asking?.cancel()
        guard !Self.isBlank(text) else { return }
        asking = Task { [weak self, pause] in
            try? await Task.sleep(for: pause)
            guard !Task.isCancelled else { return }
            // Offline, the local results stand on their own.
            try? await self?.ask(for: text)
        }
    }

    /// Asks the provider again now, as pull to refresh does.
    public func refresh() async throws {
        guard !Self.isBlank(text) else { return }
        try await ask(for: text)
    }

    private func ask(for text: String) async throws {
        let ids = try await remote(text)
        guard self.text == text else { return }
        follow(including: ids)
    }

    private func follow(including ids: [ThreadSummary.ID]) {
        following?.cancel()
        guard let continuation else { return }
        let stream = local(text, ids)
        following = Task {
            do {
                for try await threads in stream {
                    guard !Task.isCancelled else { return }
                    continuation.yield(threads)
                }
            } catch {
                if !Task.isCancelled { continuation.finish(throwing: error) }
            }
        }
    }

    private static func isBlank(_ text: String) -> Bool {
        text.allSatisfy(\.isWhitespace)
    }
}
