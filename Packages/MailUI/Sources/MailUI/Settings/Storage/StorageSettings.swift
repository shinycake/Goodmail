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

    /// What the page shows of the downloaded mail.
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

    /// The work on the cache under way, and what the last work found. Only `transition(to:)` changes it.
    private var work = Work.idle(.nothing)

    private enum Work {
        /// Nothing under way.
        case idle(Finding)
        /// Trimming the cache to the size chosen, then measuring it, with what was found before still on show.
        case fitting(Task<Void, Never>, showing: Finding)
        /// Removing all the downloaded mail, then measuring what is left. Fitting a size waits for it rather than
        /// cutting in.
        case clearing(Task<Void, Never>)
    }

    /// What the last trim and measure found.
    private enum Finding {
        /// Nothing measured yet.
        case nothing
        case usage(Usage)
        case failure(Failure)

        var phase: Phase {
            switch self {
            case .nothing: .measuring
            case .usage(let usage): .measured(usage)
            case .failure(let failure): .failed(failure)
            }
        }
    }

    var phase: Phase {
        switch work {
        case .idle(let found), .fitting(_, showing: let found): found.phase
        case .clearing: .clearing
        }
    }

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

    public init(service: Service, preferences: StoragePreferences) {
        self.service = service
        self.preferences = preferences
        scope = preferences.prefetchScope
        limit = preferences.cacheLimit
    }

    /// Trims the cache to the size chosen, as a smaller one asks, and measures what it takes then; a fit already
    /// under way gives way to it. While the mail is being removed it waits for the removal rather than cutting in,
    /// then fits. Cancelling the caller, as the page going, stops the fit, and the page shows what it showed
    /// before.
    func apply() async {
        let fit: Task<Void, Never>
        let showing: Finding
        switch work {
        case .clearing(let clearing):
            await clearing.value
            // The size still applies once the removal is done, as when it failed and left the mail in place.
            guard !Task.isCancelled else { return }
            return await apply()
        case .idle(let found), .fitting(_, showing: let found):
            let size = limit
            showing = found
            fit = Task { await self.run(trimming: size) }
            transition(to: .fitting(fit, showing: found))
        }
        await withTaskCancellationHandler {
            await fit.value
        } onCancel: {
            fit.cancel()
        }
        if case .fitting(let current, _) = work, current == fit { transition(to: .idle(showing)) }
    }

    /// Removes the downloaded mail, unless a removal is already under way, and measures what is left. Lists and
    /// search keep working, and a message downloads again when it opens. The removal is the model's own: it goes on
    /// when the page is left.
    func clear() {
        if case .clearing = work { return }
        transition(to: .clearing(Task { await self.run(trimming: 0) }))
    }

    /// Waits for the work under way, if any.
    func settled() async {
        switch work {
        case .fitting(let task, _), .clearing(let task): await task.value
        case .idle: break
        }
    }

    /// The one place `work` changes: work it replaces is stopped, and what that work would find is dropped.
    private func transition(to next: Work) {
        switch work {
        case .fitting(let task, _), .clearing(let task): task.cancel()
        case .idle: break
        }
        work = next
    }

    /// Trims the cache to `size`, then measures it, and shows what it found. Stopped, it shows nothing, as what
    /// stopped it shows its own: a cancellation is no failure.
    private func run(trimming size: Int) async {
        let found: Finding
        do {
            try await service.trim(size)
            try Task.checkCancellation()
            do {
                found = .usage(try await service.usage())
            } catch {
                found = .failure(.measuring)
            }
        } catch {
            found = .failure(.removing)
        }
        guard !Task.isCancelled else { return }
        transition(to: .idle(found))
    }
}
