public import Foundation

/// Messages' raw sources, kept for a moment after they download, for a provider whose parts can only be read from the
/// whole message (Outlook, IMAP). A body's inline images, each a part of the same message, then download it once:
/// fetches of one message under way at once are joined, and one that just finished is reused.
public actor RecentSources {
    /// How long a source is kept after it downloads: long enough for the body it came with to ask for its images.
    public static let lifetime = Duration.seconds(30)
    /// The most kept at once; a source bigger than that is never kept.
    public static let byteLimit = 16 << 20

    private enum Entry {
        case fetching(Task<Data?, any Error>)
        case kept(Data?, until: ContinuousClock.Instant)
    }

    private var entries: [String: Entry] = [:]
    private let clock = ContinuousClock()
    private let lifetime: Duration
    private let byteLimit: Int

    public init(lifetime: Duration = RecentSources.lifetime, byteLimit: Int = RecentSources.byteLimit) {
        self.lifetime = lifetime
        self.byteLimit = byteLimit
    }

    /// The message's source, `nil` when it's gone: kept, joined, or fetched with `fetch`.
    public func source(of messageID: String, fetch: @escaping @Sendable () async throws -> Data?) async throws -> Data?
    {
        dropExpired()
        switch entries[messageID] {
        case .kept(let data, _):
            return data
        case .fetching(let task):
            return try await task.value
        case nil:
            let task = Task { try await fetch() }
            entries[messageID] = .fetching(task)
            do {
                let data = try await task.value
                keep(data, for: messageID)
                return data
            } catch {
                entries[messageID] = nil
                throw error
            }
        }
    }

    private func keep(_ data: Data?, for messageID: String) {
        let kept = entries.values.reduce(0) { total, entry in
            if case .kept(let data?, _) = entry { total + data.count } else { total }
        }
        guard kept + (data?.count ?? 0) <= byteLimit else {
            entries[messageID] = nil
            return
        }
        entries[messageID] = .kept(data, until: clock.now + lifetime)
    }

    private func dropExpired() {
        let now = clock.now
        entries = entries.filter { _, entry in
            if case .kept(_, let until) = entry { until > now } else { true }
        }
    }
}
