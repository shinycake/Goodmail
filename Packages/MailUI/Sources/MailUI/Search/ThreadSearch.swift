import Foundation
public import MailCore

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
    /// Where asking the provider about the text stands. Each new text replaces it whole.
    private var asked = Asked.nothing
    private var continuation: AsyncThrowingStream<[ThreadSummary], any Error>.Continuation?
    private var following: Task<Void, Never>?

    public init(local: @escaping Local, remote: @escaping Remote, pause: Duration = .milliseconds(400)) {
        self.local = local
        self.remote = remote
        self.pause = pause
    }

    deinit {
        following?.cancel()
        asked.call?.end(.success(()))
    }

    /// The results for the current text, updated as it changes. One reader at a time: a new call ends the last.
    public func results() -> AsyncThrowingStream<[ThreadSummary], any Error> {
        continuation?.finish()
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: [ThreadSummary].self)
        self.continuation = continuation
        follow(including: asked.found)
        return stream
    }

    public func update(_ text: String) {
        guard text != self.text else { return }
        self.text = text
        follow(including: [])
        guard !Self.isBlank(text) else { return replace(with: .nothing) }
        let asking = Task { [weak self, pause] in
            guard (try? await Task.sleep(for: pause)) != nil else { return }
            await self?.firstPage(for: text)
        }
        replace(with: .asking(Call(asking)))
    }

    /// Asks the provider again now, as pull to refresh does. What it found so far stays until the answer replaces it,
    /// and stays if the answer fails, as offline.
    public func refresh() async throws {
        guard !Self.isBlank(text) else { return }
        let asking = Task { [weak self, text] in _ = await self?.firstPage(for: text) }
        switch asked {
        case .nothing, .asking:
            replace(with: .asking(Call(asking)))
        case .paged(let found, let last), .fetchingMore(let found, let last, _), .refreshing(let found, let last, _):
            replace(with: .refreshing(found, last: last, Call(asking)))
        }
        try await waitForCall()
    }

    /// Whether the provider has a next page for the current text to fetch now: not before its first page arrives,
    /// nor after its last, nor while it is asked again or a page is on its way.
    public var hasMore: Bool {
        guard case .paged(_, let last) = asked else { return false }
        return last.hasMore
    }

    /// Fetches the provider's next page for the current text, if it has one, or waits for the one on its way; call as
    /// the list nears its end. Returns once the page has come, or once the text changes, which drops it.
    public func loadMore() async throws {
        switch asked {
        case .nothing, .asking, .refreshing:
            return
        case .fetchingMore:
            try await waitForCall()
        case .paged(let found, let last):
            guard last.hasMore else { return }
            let text = text
            let fetching = Task { [weak self] in _ = await self?.nextPage(for: text, after: last, adding: found) }
            replace(with: .fetchingMore(found, last: last, Call(fetching)))
            try await waitForCall()
        }
    }

    /// The one place `asked` changes. The call it held, if any, is cancelled, and those waiting for it hear `ended`:
    /// its own outcome when it is what finished, otherwise nothing, as an answer for a text no longer searched is
    /// dropped.
    private func replace(with new: Asked, ended: Result<Void, any Error> = .success(())) {
        let old = asked
        asked = new
        old.call?.end(ended)
    }

    /// Waits for the call `asked` holds to finish or be replaced, or for the waiting task to be cancelled.
    private func waitForCall() async throws {
        let waiter = Waiter()
        if !asked.wait(waiter) { return }
        try await withTaskCancellationHandler {
            try await waiter.wait()
        } onCancel: {
            waiter.resume(.failure(CancellationError()))
        }
    }

    private func firstPage(for text: String) async {
        do {
            let page = try await remote(text, nil)
            guard !Task.isCancelled else { return }
            replace(with: .paged(page.ids, last: page))
            follow(including: asked.found)
        } catch {
            guard !Task.isCancelled else { return }
            // Asked again, the matches found before stand.
            let before: Asked =
                if case .refreshing(let found, let last, _) = asked { .paged(found, last: last) } else { .nothing }
            replace(with: before, ended: .failure(error))
        }
    }

    private func nextPage(for text: String, after last: SearchPage, adding found: [ThreadSummary.ID]) async {
        do {
            let page = try await remote(text, last)
            guard !Task.isCancelled else { return }
            replace(with: .paged(found + page.ids, last: page))
            follow(including: asked.found)
        } catch {
            // The next approach to the end asks again.
            guard !Task.isCancelled else { return }
            replace(with: .paged(found, last: last), ended: .failure(error))
        }
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
