import Foundation
import MailCore
import Testing

@testable import MailUI

/// The rules Settings shows: a change shows at once, a save that fails says why without losing it, and reading them
/// again never undoes a save still under way.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct MailRulesTests {
    private struct Refused: LocalizedError {
        var errorDescription: String? { "Refused" }
    }

    private let star = MailRule(name: "Star all", condition: .all([]), actions: [.star])
    private let archive = MailRule(name: "Archive all", condition: .all([]), actions: [.archive])

    /// A store whose saves wait for `open`, as a slow disk or network would.
    @MainActor
    private final class SlowStore {
        var stored: [MailRule] = []
        let (gate, open) = AsyncStream<Void>.makeStream()

        var service: MailRules.Service {
            MailRules.Service(
                load: { [self] in stored },
                save: { [self] rules in
                    for await _ in gate { break }
                    stored = rules
                }, labelNames: { [] })
        }
    }

    @Test func aFailedSaveKeepsTheChangeAndSaysWhyUntilDismissed() async {
        let rules = MailRules(
            service: MailRules.Service(load: { [] }, save: { _ in throw Refused() }, labelNames: { [] }))
        await rules.load()

        rules.save(star)
        await rules.settled()

        #expect(rules.state == .loaded([star], saveFailure: "Refused"))
        #expect(rules.saveFailure == "Refused")
        rules.dismissSaveFailure()
        #expect(rules.state == .loaded([star], saveFailure: nil))
    }

    @Test func appearingAgainBeforeASaveRanKeepsTheChange() async {
        let store = SlowStore()
        let rules = MailRules(service: store.service)
        await rules.load()

        rules.save(star)
        let reading = Task { await rules.load() }
        for _ in 0..<10 { await Task.yield() }
        #expect(rules.state == .loaded([star], saveFailure: nil), "the change stays shown while the save waits")
        store.open.yield()
        await reading.value

        #expect(rules.state == .loaded([star], saveFailure: nil), "the read comes after the save")
        #expect(store.stored == [star])
    }

    @Test func aScreenOpenedAgainReadsOnlyOnceTheLastOnesSaveRan() async {
        // Back out of Rules and in again: the new screen has its own rules, over the same service.
        let store = SlowStore()
        let service = store.service
        let first = MailRules(service: service)
        await first.load()
        first.save(star)

        let second = MailRules(service: service)
        let reading = Task { await second.load() }
        for _ in 0..<10 { await Task.yield() }
        store.open.yield()
        await reading.value

        #expect(second.state == .loaded([star], saveFailure: nil))
    }

    @Test func aChangeMadeWhileTheRulesAreReadStaysAsShown() async {
        var stored: [MailRule] = []
        let (gate, open) = AsyncStream<Void>.makeStream()
        var gated = false
        let rules = MailRules(
            service: MailRules.Service(
                load: {
                    if gated { for await _ in gate { break } }
                    return stored
                },
                save: { stored = $0 }, labelNames: { [] }))
        await rules.load()

        gated = true
        let reading = Task { await rules.load() }
        for _ in 0..<10 { await Task.yield() }
        rules.save(star)
        open.yield()
        await reading.value
        await rules.settled()

        #expect(rules.state == .loaded([star], saveFailure: nil))
        #expect(stored == [star])
    }

    @Test func appearingAgainShowsRulesChangedElsewhere() async {
        var stored = [star]
        let rules = MailRules(service: MailRules.Service(load: { stored }, save: { _ in }, labelNames: { [] }))
        await rules.load()

        stored = [star, archive]
        await rules.load()

        #expect(rules.state == .loaded([star, archive], saveFailure: nil))
    }

    @Test func aSavedChangeShowsNoFailure() async {
        var saved: [[MailRule]] = []
        let rules = MailRules(
            service: MailRules.Service(load: { [] }, save: { saved.append($0) }, labelNames: { [] }))
        await rules.load()

        rules.save(star)
        await rules.settled()

        #expect(saved == [[star]])
        #expect(rules.saveFailure == nil)
    }
}
