import Foundation
import MailCore

/// Search as the user types: the store's matches at once, then the provider's merged in once typing pauses, and its
/// further pages as the list nears its end.
public final class ThreadSearch {
    /// The store's threads matching the text, together with the given provider matches.
    public typealias Local = (String, [ThreadSummary.ID]) -> AsyncThrowingStream<[ThreadSummary], any Error>
    /// The provider's matches for the text: its first page, or the page after the given one.
    public typealias Remote = (String, SearchPage?) async throws -> SearchPage

    private let local: Local
    private let remote: Remote
    private let pause: Duration
    /// What is being searched for now.
    public private(set) var text = ""
    /// The provider's matches for the text so far, and the last page of them, which says where the next starts.
    private var found: [ThreadSummary.ID] = []
    private var lastPage: SearchPage?
    private var isLoadingMore = false
    private var continuation: AsyncThrowingStream<[ThreadSummary], any Error>.Continuation?
    private var following: Task<Void, Never>?
    private var asking: Task<Void, Never>?

    public init(local: @escaping Local, remote: @escaping Remote, pause: Duration = .milliseconds(400)) {
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
        follow(including: found)
        return stream
    }

    public func update(_ text: String) {
        guard text != self.text else { return }
        self.text = text
        found = []
        lastPage = nil
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

    /// Fetches the provider's next page for the current text, if it has one; call as the list nears its end.
    /// Before the first page arrives, and after the last, there is nothing to fetch.
    public func loadMore() async throws {
        guard let lastPage, lastPage.hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let text = text
        let page = try await remote(text, lastPage)
        // The text changed, or a refresh started the matches over, while this page was on its way.
        guard self.text == text, self.lastPage == lastPage else { return }
        found += page.ids
        self.lastPage = page
        follow(including: found)
    }

    private func ask(for text: String) async throws {
        let page = try await remote(text, nil)
        guard self.text == text else { return }
        found = page.ids
        lastPage = page
        follow(including: found)
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
