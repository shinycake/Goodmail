import Foundation
import MailCore
import Testing

@testable import MailUI

@MainActor
struct BadgeChoicesTests {
    private let gmail = Account(id: AccountID(rawValue: "g"), email: "me@gmail.com", color: .orange, service: .gmail)
    private let icloud = Account(id: AccountID(rawValue: "i"), email: "me@icloud.com", color: .blue, service: .icloud)

    @Test func primaryOnlyIsOfferedWhereTheInboxIsSorted() {
        #expect(BadgeChoices.choices(for: gmail, sorted: true, current: .inbox) == [.inbox, .primary, .off])
        #expect(BadgeChoices.choices(for: gmail, sorted: false, current: .inbox) == [.inbox, .off])
        #expect(BadgeChoices.choices(for: icloud, sorted: true, current: .inbox) == [.inbox, .off])
    }

    @Test func aStoredPrimaryChoiceStaysVisibleAfterSortingIsTurnedOff() {
        #expect(BadgeChoices.choices(for: gmail, sorted: false, current: .primary) == [.inbox, .primary, .off])
    }

    @Test func aChoiceShowsAtOnceAndIsStored() async {
        var stored: [BadgeSource] = []
        let choices = BadgeChoices(
            read: { [gmail] in [gmail.id: .inbox] }, store: { source, _ in stored.append(source) },
            turnedOff: { true })
        await choices.load()
        #expect(choices.choice(for: gmail.id) == .inbox)
        #expect(choices.isTurnedOffInSettings)

        choices.set(.off, for: gmail.id)
        #expect(choices.choice(for: gmail.id) == .off)
        await choices.settled()
        #expect(stored == [.off])
    }

    @Test func nothingIsShownOrSaidOffBeforeTheChoicesAreRead() {
        let choices = BadgeChoices(read: { [:] }, store: { _, _ in }, turnedOff: { true })
        guard case .loading = choices.status else {
            Issue.record("not loading: \(choices.status)")
            return
        }
        #expect(choices.choice(for: gmail.id) == nil)
        #expect(!choices.isTurnedOffInSettings)
    }

    @Test func readingAgainWhileAChoiceIsStoredDoesNotUndoIt() async {
        // A store that hasn't finished when the screen appears again, which reads the old choice back meanwhile.
        var stored: [AccountID: BadgeSource] = [:]
        let (gate, open) = AsyncStream<Void>.makeStream()
        let choices = BadgeChoices(
            read: { [gmail] in [gmail.id: stored[gmail.id] ?? .inbox] },
            store: { source, id in
                for await _ in gate { break }
                stored[id] = source
            },
            turnedOff: { false })
        await choices.load()

        choices.set(.off, for: gmail.id)
        let reading = Task { await choices.load() }
        for _ in 0..<10 { await Task.yield() }
        #expect(choices.choice(for: gmail.id) == .off, "the picker doesn't jump back")
        open.yield()
        await reading.value

        #expect(choices.choice(for: gmail.id) == .off)
    }

    @Test func aChoiceMadeWhileAReadIsUnderWayStaysAsShown() async {
        let (gate, open) = AsyncStream<Void>.makeStream()
        var gated = false
        let choices = BadgeChoices(
            read: { [gmail] in
                if gated { for await _ in gate { break } }
                return [gmail.id: .inbox]
            },
            store: { _, _ in }, turnedOff: { false })
        await choices.load()

        gated = true
        let reading = Task { await choices.load() }
        for _ in 0..<10 { await Task.yield() }
        choices.set(.off, for: gmail.id)
        open.yield()
        await reading.value

        #expect(choices.choice(for: gmail.id) == .off)
    }
}
