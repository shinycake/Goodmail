import MailCore
public import Observation

/// The Storage page's state: what the downloaded mail takes, and the reader's choices of how much to keep and download
/// ahead.
@Observable
public final class StorageSettings {
    /// The bytes the downloaded mail takes on the device.
    nonisolated public struct Usage: Equatable, Sendable {
        /// Message bodies, with their search text.
        public var messages: Int
        /// Attachments and inline images.
        public var attachments: Int
        public var total: Int { messages + attachments }

        public init(messages: Int, attachments: Int) {
            self.messages = messages
            self.attachments = attachments
        }
    }

    /// How the page measures and trims the cache.
    public struct Service {
        public let usage: () async throws -> Usage
        /// Removes the least recently read mail until the cache fits the size; zero removes all it can.
        public let trim: (Int) async throws -> Void

        public init(usage: @escaping () async throws -> Usage, trim: @escaping (Int) async throws -> Void) {
            self.usage = usage
            self.trim = trim
        }
    }

    enum Phase: Equatable {
        case measuring
        case measured(Usage)
        /// Removing all downloaded mail; the usage is measured again after.
        case clearing
        case failed(Failure)
    }

    enum Failure: Equatable {
        /// The space the mail takes couldn't be read.
        case measuring
        /// Mail couldn't be removed to fit the size chosen, or at all.
        case removing
    }

    private(set) var phase = Phase.measuring
    var scope: PrefetchScope {
        didSet { preferences.prefetchScope = scope }
    }
    var limit: Int {
        didSet { preferences.cacheLimit = limit }
    }
    /// The sizes this kind of device offers.
    var limitChoices: [Int] { preferences.window.cacheLimitChoices }
    @ObservationIgnored private let preferences: StoragePreferences
    @ObservationIgnored private let service: Service
    /// How many removals have started, so a trim to a size that a removal followed doesn't report over it.
    @ObservationIgnored private var removals = 0

    public init(service: Service, preferences: StoragePreferences) {
        self.service = service
        self.preferences = preferences
        scope = preferences.prefetchScope
        limit = preferences.cacheLimit
    }

    /// Trims the cache to the size chosen, as a smaller one asks, and measures what it takes then.
    func apply() async {
        let removalsBefore = removals
        let outcome = await trimmed(to: limit)
        // Removing all the mail takes over from fitting a size: a trim a removal followed doesn't report over it.
        if removals == removalsBefore { phase = outcome }
    }

    /// Removes the downloaded mail. Lists and search keep working, and a message downloads again when it opens.
    func clear() async {
        removals += 1
        phase = .clearing
        phase = await trimmed(to: 0)
    }

    private func trimmed(to size: Int) async -> Phase {
        do {
            try await service.trim(size)
        } catch {
            return .failed(.removing)
        }
        do {
            return .measured(try await service.usage())
        } catch {
            return .failed(.measuring)
        }
    }
}
