import MailCore
import Testing

@testable import MailUI

/// The Storage page: it measures the downloaded mail, trims it to the size chosen, and removes it on request.
@MainActor
@Suite(.timeLimit(.minutes(1)))
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

    /// Holds every trim until the test lets them go, as a slow database would. A trim whose work was stopped meanwhile
    /// throws, as one cut short does.
    @MainActor
    final class HeldCache {
        var usage = StorageSettings.Usage(messages: 300, attachments: 50)
        /// Whether removing all the mail fails, leaving it in place.
        var removalFails = false
        private(set) var trims: [Int] = []
        private var held: [CheckedContinuation<Void, Never>] = []

        struct Locked: Error {}

        var service: StorageSettings.Service {
            StorageSettings.Service(
                usage: { self.usage },
                trim: { size in
                    self.trims.append(size)
                    await withCheckedContinuation { self.held.append($0) }
                    try Task.checkCancellation()
                    if size == 0 {
                        if self.removalFails { throw Locked() }
                        self.usage = .init(messages: 0, attachments: 0)
                    }
                })
        }

        /// Waits until `count` trims are held.
        func holding(_ count: Int) async {
            while held.count < count { await Task.yield() }
        }

        func release() {
            for trim in held { trim.resume() }
            held = []
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
        model.clear()
        await model.settled()
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
        let cache = HeldCache()
        let model = StorageSettings(service: cache.service, preferences: Self.handheld)
        async let applied: Void = model.apply()
        await cache.holding(1)
        model.clear()
        await cache.holding(2)
        cache.release()
        await applied
        await model.settled()
        #expect(model.phase == .measured(.init(messages: 0, attachments: 0)), "the page keeps what removing found")
    }

    /// Choosing another size during Remove All neither trims over the removal nor lets Remove start again; the size
    /// is fitted once the removal is done.
    @Test func aSizeChosenWhileTheMailIsRemovedWaitsForTheRemoval() async {
        let cache = HeldCache()
        let model = StorageSettings(service: cache.service, preferences: Self.handheld)
        model.clear()
        await cache.holding(1)
        async let applied: Void = model.apply()
        for _ in 0..<20 { await Task.yield() }
        #expect(model.phase == .clearing, "Remove stays off while the mail goes")
        model.clear()
        #expect(cache.trims == [0], "no second removal, and no trim to the size")
        cache.release()
        await cache.holding(1)
        #expect(cache.trims == [0, model.limit], "the size is fitted after the removal")
        cache.release()
        await applied
        #expect(model.phase == .measured(.init(messages: 0, attachments: 0)))
    }

    /// A removal that fails leaves the mail in place, so the size chosen meanwhile is still fitted.
    @Test func aSizeChosenDuringARemovalThatFailsIsStillFitted() async {
        let cache = HeldCache()
        cache.removalFails = true
        let model = StorageSettings(service: cache.service, preferences: Self.handheld)
        model.clear()
        await cache.holding(1)
        async let applied: Void = model.apply()
        for _ in 0..<20 { await Task.yield() }
        cache.release()
        await cache.holding(1)
        cache.release()
        await applied
        #expect(cache.trims == [0, model.limit])
        #expect(model.phase == .measured(.init(messages: 300, attachments: 50)))
    }

    /// Leaving the page while a size is fitted stops the fit, which says nothing went wrong.
    @Test func aFitStoppedByLeavingThePageIsNoFailure() async {
        let cache = HeldCache()
        let model = StorageSettings(service: cache.service, preferences: Self.handheld)
        let page = Task { await model.apply() }
        await cache.holding(1)
        page.cancel()
        cache.release()
        await page.value
        #expect(model.phase == .measuring, "back to what it showed before the fit")
    }

    @Test func aRemovalThatFailsSaysSo() async {
        struct Locked: Error {}
        let model = StorageSettings(
            service: .init(usage: { .init(messages: 300, attachments: 50) }, trim: { _ in throw Locked() }),
            preferences: Self.handheld)
        model.clear()
        await model.settled()
        #expect(model.phase == .failed(.removing))
    }
}
