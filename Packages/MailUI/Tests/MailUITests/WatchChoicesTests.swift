import Foundation
import Testing

@testable import MailUI

@MainActor
struct WatchChoicesTests {
    private let defaults = UserDefaults(suiteName: "WatchChoicesTests-\(UUID().uuidString)")!

    @Test func theWatchReadsMailItselfUntilTheOwnerSaysOtherwise() {
        #expect(WatchChoices.mailWithoutIPhone(in: defaults))
        #expect(WatchChoices(defaults: defaults) {}.mailWithoutIPhone)
    }

    @Test func aChangeIsKeptAndTold() {
        var told = 0
        let choices = WatchChoices(defaults: defaults) { told += 1 }

        choices.mailWithoutIPhone = false
        choices.mailWithoutIPhone = false

        #expect(told == 1, "setting the same value again tells nothing")
        #expect(!WatchChoices.mailWithoutIPhone(in: defaults))
        #expect(!WatchChoices(defaults: defaults) {}.mailWithoutIPhone)
    }
}
