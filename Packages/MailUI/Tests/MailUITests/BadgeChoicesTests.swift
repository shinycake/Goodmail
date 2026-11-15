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
        #expect(choices.sources == [gmail.id: BadgeSource.inbox])
        #expect(choices.isTurnedOffInSettings)

        await choices.set(.off, for: gmail.id)
        #expect(choices.sources[gmail.id] == .off)
        #expect(stored == [.off])
    }
}
