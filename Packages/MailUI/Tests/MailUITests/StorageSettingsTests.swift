import MailCore
import Testing

@testable import MailUI

/// The Storage page: it measures the downloaded mail, trims it to the size chosen, and removes it on request.
@MainActor
struct StorageSettingsTests {
    private static let handheld = StoragePreferences(window: .handheld)

    /// Keeps the trims asked for, and measures what is left.
    @MainActor
    final class Cache {
        private(set) var trims: [Int] = []
        private var usage = StorageSettings.Usage(messages: 300, attachments: 50)

        var service: StorageSettings.Service {
            StorageSettings.Service(
                usage: { self.usage },
                trim: { limit in
                    self.trims.append(limit)
                    if limit == 0 { self.usage = .init(messages: 0, attachments: 0) }
                })
        }
    }

    /// Removes all at once, but holds a trim to a size until the test lets it go.
    @MainActor
    final class SlowCache {
        var usage = StorageSettings.Usage(messages: 300, attachments: 50)
        private(set) var fitting: CheckedContinuation<Void, Never>?

        var service: StorageSettings.Service {
            StorageSettings.Service(
                usage: { self.usage },
                trim: { size in
                    if size == 0 {
                        self.usage = .init(messages: 0, attachments: 0)
                    } else {
                        await withCheckedContinuation { self.fitting = $0 }
                    }
                })
        }
    }

    @Test func applyingTheLimitTrimsToItAndMeasures() async {
        let cache = Cache()
        let model = StorageSettings(service: cache.service, preferences: Self.handheld)
        #expect(model.phase == .measuring)
        await model.apply()
        #expect(cache.trims == [model.limit])
        #expect(model.phase == .measured(.init(messages: 300, attachments: 50)))
    }

    @Test func removingTheDownloadedMailTrimsItAll() async {
        let cache = Cache()
        let model = StorageSettings(service: cache.service, preferences: Self.handheld)
        await model.clear()
        #expect(cache.trims == [0])
        #expect(model.phase == .measured(.init(messages: 0, attachments: 0)))
    }

    @Test func aMeasureThatFailsSaysSo() async {
        struct Unreadable: Error {}
        let model = StorageSettings(
            service: .init(usage: { throw Unreadable() }, trim: { _ in }), preferences: Self.handheld)
        await model.apply()
        #expect(model.phase == .failed(.measuring))
    }

    @Test func removingTheMailOutlastsFittingASizeStartedBefore() async {
        let cache = SlowCache()
        let model = StorageSettings(service: cache.service, preferences: Self.handheld)
        async let applied: Void = model.apply()
        while cache.fitting == nil { await Task.yield() }
        await model.clear()
        // The size's trim finishes last and measures something else; the page keeps what removing found.
        cache.usage = .init(messages: 7, attachments: 7)
        cache.fitting?.resume()
        await applied
        #expect(model.phase == .measured(.init(messages: 0, attachments: 0)))
    }

    @Test func aRemovalThatFailsSaysSo() async {
        struct Locked: Error {}
        let model = StorageSettings(
            service: .init(usage: { .init(messages: 300, attachments: 50) }, trim: { _ in throw Locked() }),
            preferences: Self.handheld)
        await model.clear()
        #expect(model.phase == .failed(.removing))
    }
}
